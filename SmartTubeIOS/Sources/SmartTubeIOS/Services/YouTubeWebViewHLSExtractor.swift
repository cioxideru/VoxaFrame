#if canImport(WebKit)
import WebKit
import JavaScriptCore
import os
import SmartTubeIOSCore

private let extractLog = Logger(subsystem: appSubsystem, category: "WebViewHLS")

/// Extracts a YouTube HLS manifest URL by loading the YouTube watch page in a hidden
/// WKWebView and intercepting the YouTube JavaScript player's internal `youtubei/v1/player`
/// network call.
///
/// **Why this works:**
/// YouTube generates HLS manifest URLs with `spc=` (proof-of-context) tokens only when the
/// request originates from a real browser JavaScript execution context. The `spc=` token is
/// computed by the YouTube player JS and makes HLS segment URLs work without `rqh=1` CDN
/// restrictions. Raw InnerTube API calls (even with Bearer auth) cannot generate `spc=` because
/// they lack the JavaScript execution context that YouTube's server verifies.
///
/// By running YouTube's JS player in WKWebView, the player computes `spc=` and includes it in
/// its internal `youtubei/v1/player` call. We intercept that response using JavaScript
/// XHR/fetch hooks and forward the `hlsManifestUrl` to Swift via `WKScriptMessageHandler`.
///
/// This approach works on both iOS Simulator and real device without any external tools.
@MainActor
final class YouTubeWebViewHLSExtractor: NSObject {

    static let shared = YouTubeWebViewHLSExtractor()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<URL?, Never>?
    private var timeoutTask: Task<Void, Never>?
    /// Incremented each time `extractHLSURL` starts a new extraction. Timeout tasks
    /// capture their generation at creation time and bail out if it has changed,
    /// preventing a cancelled previous-extraction timeout from firing on the current
    /// extraction's continuation (ABA problem with the `continuation != nil` guard).
    private var extractionGeneration: Int = 0
    /// The video ID currently being extracted, set at the start of `extractHLSURL` and
    /// cleared in `finish`. Allows callers to detect a same-video in-flight extraction
    /// and await it via `awaitCurrentExtraction()` instead of cancelling it.
    private(set) var currentExtractionVideoId: String? = nil
    /// After `extractHLSURL` completes, holds the n-challenge mapping solved in-JS.
    /// `nil` when the URL had no `/n/` or the solver wasn't available.
    private(set) var extractedNSolver: (unsolved: String, solved: String)?
    /// The pot= token extracted from the YouTube player's /player API request body,
    /// set alongside `extractedNSolver` when the JS interceptor finds one in
    /// `serviceIntegrityDimensions.poToken`. Nil when the player made no BotGuard call.
    private(set) var extractedPoToken: String?
    /// Additional continuations registered via `awaitCurrentExtraction()`. When `finish()`
    /// fires, all extra continuations receive the same URL result as the primary continuation.
    private var extraContinuations: [CheckedContinuation<URL?, Never>] = []
    /// The last task created by `serialExtract()`. Each new serialExtract call chains onto
    /// this task, ensuring strict sequential execution of serial extractions.
    private var pendingSerialTask: Task<URL?, Never>? = nil
    /// Epoch counter incremented by `priorityExtract` on every user-initiated load.
    /// A `serialExtract` task that wakes up after waiting for its predecessor will
    /// compare its captured epoch with the current epoch: if they differ, a priority
    /// extract has taken over and the serial task must await `pendingSerialTask`
    /// (the priority task) rather than call `extractHLSURL` and cancel it.
    private var serialTaskEpoch: Int = 0
    /// The videoId passed to the most recent `priorityExtract` call.
    /// Used by `serialExtract`'s stale-epoch branch to decide whether the priority
    /// task's URL is safe to return: if the priority task was for a *different* video,
    /// returning its URL would poison the caller's cache entry with the wrong stream.
    private var pendingSerialTaskVideoId: String? = nil

    // MARK: - Public API

    /// Re-entrance guard: `true` while a `preWarm()` extraction is in progress.
    /// Prevents concurrent VideoCardView tasks from stacking `serialExtract` calls into a
    /// long sequential chain. Each card that sees `isPreWarming=true` returns immediately;
    /// after the current extraction finishes, the next idle card (via retry) can start one.
    static var isPreWarming = false

    /// Maximum number of card tasks that may enter the preWarm loop simultaneously.
    /// Each loop iteration takes ~2.5 s (warm extraction). Limiting to 3 means at most
    /// 3 cards queue up for preWarm at any time; cards beyond that skip the loop entirely
    /// and rely on the tap-time extraction instead. Reduces background CPU when the home
    /// feed has 15+ visible cards each spinning their own preWarm task.
    static let maxPreWarmLoops: Int = 3
    /// Current number of active VideoCardView preWarm loops. @MainActor-isolated — only
    /// mutated from the card's .task modifier (which runs on MainActor).
    static var activePreWarmLoops: Int = 0

    /// Pre-warms the WKWebView HLS extraction for `videoId` and stores the result in
    /// `VideoPreloadCache`. Called speculatively on card appear so that if the user taps,
    /// Phase -1a can play from the cached URL instead of waiting ~3 s for a live extraction.
    ///
    /// Non-queueing: if an extraction is already in progress (`isPreWarming`), returns
    /// immediately. Callers should retry after a delay that exceeds typical extraction time
    /// (~3 s) so the extractor is idle on the second attempt. Callers must guard
    /// `!video.isShort` before calling so that Shorts (which never trigger
    /// `youtubei/v1/player`) don't block the chain with a 40 s timeout.
    static func preWarm(videoId: String) async {
        guard !isPreWarming else { return }
        guard await VideoPreloadCache.shared.cachedWKHLSURL(for: videoId) == nil else { return }
        // Re-check after the async suspension: a concurrent task may have set isPreWarming
        // while the cache check was suspended. @MainActor isolation makes this check-then-set
        // atomic with respect to other MainActor tasks (no await between the guard and the set).
        guard !isPreWarming else { return }
        isPreWarming = true
        defer { isPreWarming = false }
        // Use serialExtract (NOT extractHLSURL) so this task joins the pendingSerialTask
        // chain. load()'s own serialExtract call chains AFTER this task instead of
        // calling finish(url:nil) to cancel it. The URL is stored in cache before the
        // Darwin notification fires; Phase -1a reads it on the next load() and fast-starts
        // without waiting for the race (cold cycle ≈ hot cycle, ~0.5s).
        guard let url = await shared.serialExtract(videoId: videoId) else { return }
        // fix21: Capture extractedPoToken NOW, before the first `await` below.
        // The `await VideoPreloadCache.shared.store(wkHLSManifestURL:)` call yields the
        // @MainActor, allowing other MainActor tasks to run. If loadAsync's wkHLSEarlyTask
        // is queued (it chains onto pendingSerialTask), it can start executing and call
        // extractHLSURL which resets extractedPoToken = nil at line 117. Capturing into a
        // local `let` before any `await` holds the value regardless of subsequent resets.
        let capturedPoToken = shared.extractedPoToken
        await VideoPreloadCache.shared.store(wkHLSManifestURL: url, for: videoId, isPreWarm: true)
        if let pot = capturedPoToken {
            await VideoPreloadCache.shared.store(wkHLSPoToken: pot, for: videoId)
        }
        // fix26b: Notification removed from preWarm(). VideoCardView's heartbeat loop
        // fires prewarm.done.<videoId> AFTER the second serialExtract completes, so the
        // test always taps into a live CDN session (not the preWarm session which is
        // immediately invalidated by earlyTask's wv.load() call).
    }

    /// Loads the YouTube watch page for `videoId` in a hidden WKWebView, waits for the
    /// YouTube JS player to make its internal `youtubei/v1/player` call, and returns
    /// the `hlsManifestUrl` from that response.
    ///
    /// - Parameter videoId: The YouTube video ID.
    /// - Parameter timeoutSeconds: How long to wait before giving up. Default 20 s.
    /// - Returns: The HLS master manifest URL (may include `spc=`), or `nil` on failure/timeout.
    func extractHLSURL(videoId: String, timeoutSeconds: Double = 40) async -> URL? {
        // Cancel any pending extraction before starting a new one.
        finish(url: nil)
        extractedNSolver = nil
        extractedPoToken = nil
        extractionGeneration &+= 1
        currentExtractionVideoId = videoId

        extractLog.notice("⚠️ [webView] starting HLS extraction for \(videoId as NSString)")

        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.continuation = cont
            let myGeneration = self.extractionGeneration

            // fix17: Reuse the persistent WKWebView if one already exists.
            // Keeping the WKWebView alive preserves the WebContent process (JIT cache)
            // and the IndexedDB/localStorage state (YouTube's BotGuard token cache)
            // across sequential extractions:
            //   1st extraction (cold): ~40 s — BotGuard WAA pipeline runs + JIT compiles
            //   2nd extraction (reuse): ~2–5 s — IndexedDB token cached, JIT warm
            //   3rd+ extraction: ~1.8 s — fully cached
            // Without reuse, each call created a fresh WKWebView / WebContent process
            // → every extraction paid the full 40 s cold cost.
            let wv: WKWebView
            if let existing = self.webView {
                wv = existing
            } else {
                let contentController = WKUserContentController()
                contentController.add(self, name: "hlsExtractor")

                // Inject the EJS AST-based n-challenge solver (lib + core) BEFORE
                // our interceptor so that `jsc` is available when solveNFromPlayerJS runs.
                if let solverScripts = Self.ejsSolverUserScripts() {
                    for script in solverScripts {
                        contentController.addUserScript(script)
                    }
                }

                // Inject the interceptor BEFORE the document loads so it can hook into
                // XMLHttpRequest and fetch before YouTube's player JS initialises.
                contentController.addUserScript(
                    WKUserScript(
                        source: Self.interceptorJS,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    ))

                let config = WKWebViewConfiguration()
                config.userContentController = contentController
                // Allow programmatic video playback (no user gesture required) so that
                // after we get the hlsManifestUrl we can call video.play() to let the YouTube
                // player seed googlevideo.com session cookies into the WKWebView cookie store.
                config.mediaTypesRequiringUserActionForPlayback = []
                // Use .default() so existing WKWebView cookies from earlier loads are reused.
                config.websiteDataStore = .default()

                // Pre-seed the SOCS consent cookie once — it persists in the .default() store
                // across navigations so subsequent extractions don't need to re-seed it.
                let socsCookieProps: [HTTPCookiePropertyKey: Any] = [
                    .name: "SOCS",
                    .value: "CAI",
                    .domain: ".youtube.com",
                    .path: "/",
                    .secure: true,
                    .sameSitePolicy: "None",
                    .expires: Date(timeIntervalSinceNow: 365 * 24 * 3600),
                ]
                if let socsCookie = HTTPCookie(properties: socsCookieProps) {
                    config.websiteDataStore.httpCookieStore.setCookie(socsCookie)
                    extractLog.notice("[webView/HLS] SOCS consent cookie pre-seeded for .youtube.com")
                }

                // Non-zero off-screen frame so the compositor renders the video element,
                // which is required for programmatic playback on iOS.
                let newWv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
                newWv.navigationDelegate = self
                // Desktop Safari UA so YouTube serves its full player (hlsManifestUrl).
                newWv.customUserAgent =
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                    + "Version/17.5 Safari/605.1.15"
                self.webView = newWv
                wv = newWv
            }

            guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else {
                extractLog.error("❌ [webView] invalid videoId: \(videoId as NSString)")
                cont.resume(returning: Optional<URL>.none)
                self.continuation = nil
                return
            }

            var request = URLRequest(url: url)
            // Accept-Language: YouTube uses this to pick the page language; using en-US
            // avoids consent-wall redirects seen in some locales.
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            wv.load(request)

            // Timeout safety net. Captures `myGeneration` so that if `extractHLSURL`
            // is called again (cancelling this extraction), the woken-up cancelled task
            // sees a stale generation and bails — preventing it from firing on the
            // new extraction's continuation (ABA problem).
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let self, self.extractionGeneration == myGeneration else { return }
                extractLog.notice("⚠️ [webView] timed out for \(videoId as NSString)")
                self.finish(url: Optional<URL>.none)
            }
        }
    }

    /// Awaits the result of the currently in-flight extraction without cancelling it.
    /// Multiple callers (e.g. two concurrent `race failed` handlers for the same video)
    /// each append their continuation to `extraContinuations`. When `finish()` fires,
    /// all waiters receive the same URL result.
    /// Returns `nil` if no extraction is in progress.
    func awaitCurrentExtraction() async -> URL? {
        guard continuation != nil else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.extraContinuations.append(cont)
        }
    }

    /// Priority entry point for user-initiated load (earlyTask). Unlike `serialExtract`,
    /// this method does NOT wait for any in-flight background extraction. Instead it
    /// starts immediately — `extractHLSURL`'s `finish(url:nil)` cancels any active
    /// continuation, ending the background task cleanly. The new task is still registered
    /// in `pendingSerialTask` so subsequent `serialExtract` calls (from race-failed
    /// handlers) chain onto it correctly.
    ///
    /// Incrementing `serialTaskEpoch` signals every queued-but-not-yet-awoken
    /// `serialExtract` task to yield to this priority task instead of calling
    /// `extractHLSURL` and inadvertently cancelling the ongoing extraction (R14 regression:
    /// multiple VideoCardView timeout-driven tasks for `_CjIX66a9ts` woke up sequentially
    /// and each called `extractHLSURL`, cancelling `priorityExtract`'s active continuation).
    func priorityExtract(videoId: String) async -> URL? {
        serialTaskEpoch &+= 1
        pendingSerialTaskVideoId = videoId
        let newTask = Task { @MainActor [weak self] in
            guard let self else { return Optional<URL>.none }
            extractLog.notice(
                "[webView] priorityExtract(\(videoId as NSString)): starting immediately (user tap, bypasses chain)")
            return await self.extractHLSURL(videoId: videoId)
        }
        pendingSerialTask = newTask
        return await newTask.value
    }

    /// Serial-safe entry point for the fallback path. Unlike `extractHLSURL`, this method
    /// uses a task-chain to guarantee strict sequential execution: each call awaits the
    /// previous `serialExtract` task before starting a new extraction. This prevents N
    /// concurrent `race failed` handlers (across any mix of video IDs) from all waking
    /// simultaneously and cancelling each other via `finish(url: nil)`.
    ///
    /// Pattern: each call captures the previous pending task, creates a new task that
    /// awaits the previous one, then calls `extractHLSURL`. Since all callers are on
    /// the `@MainActor`, the `pendingSerialTask` assignment is safe.
    ///
    /// Epoch check: before calling `extractHLSURL`, the task compares its captured
    /// `serialTaskEpoch` with the current value. If they differ, `priorityExtract` has
    /// advanced the epoch — this task is stale and should await `pendingSerialTask`
    /// (the priority task) instead of calling `extractHLSURL` and cancelling it.
    func serialExtract(videoId: String) async -> URL? {
        let previousTask = pendingSerialTask
        let capturedEpoch = serialTaskEpoch
        let newTask = Task { @MainActor [weak self] in
            // Wait for the previous serial extraction to complete before starting ours.
            // This prevents the cancel-chain: finish(url:nil) at the top of extractHLSURL
            // cancels any pending continuation, so we must not call extractHLSURL until
            // the previous extraction has already resolved and cleared its continuation.
            _ = await previousTask?.value
            guard let self else { return Optional<URL>.none }
            // Epoch check: if priorityExtract advanced the epoch while we were waiting,
            // we are stale. Only yield to the priority task's URL if the priority task is
            // for the *same* videoId — yielding a different video's URL would poison the
            // caller's cache entry (fix10/preWarm) with the wrong stream.
            guard self.serialTaskEpoch == capturedEpoch else {
                if self.pendingSerialTaskVideoId == videoId {
                    extractLog.notice(
                        "[webView] serialExtract(\(videoId as NSString)): stale epoch, same video — yielding to priority task"
                    )
                    return await self.pendingSerialTask?.value
                } else {
                    let priorityId = self.pendingSerialTaskVideoId ?? "nil"
                    extractLog.notice(
                        "[webView] serialExtract(\(videoId as NSString)): stale epoch, priority is for different video (\(priorityId as NSString)) — returning nil to prevent cache poisoning"
                    )
                    return nil
                }
            }
            extractLog.notice("[webView] serialExtract(\(videoId as NSString)): starting (previous task done)")
            return await self.extractHLSURL(videoId: videoId)
        }
        pendingSerialTask = newTask
        return await newTask.value
    }

    // MARK: - EJS Solver Scripts

    /// Loads the yt-dlp EJS AST-based n-challenge solver scripts from the app bundle
    /// and returns them as ordered WKUserScript instances ready for injection.
    ///
    /// Injection order matters:
    ///   1. lib.min.js  — defines `var lib = {meriyah, astring}` (JS AST parser + code-gen)
    ///   2. bridge       — exposes `meriyah` and `astring` as top-level globals
    ///   3. core.min.js — defines `var jsc = (function(e,n){...})(meriyah, astring)` (solver)
    private static func ejsSolverUserScripts() -> [WKUserScript]? {
        guard let libURL = Bundle.module.url(forResource: "yt.solver.lib.min", withExtension: "js"),
            let coreURL = Bundle.module.url(forResource: "yt.solver.core.min", withExtension: "js"),
            let libCode = try? String(contentsOf: libURL, encoding: .utf8),
            let coreCode = try? String(contentsOf: coreURL, encoding: .utf8)
        else {
            extractLog.warning("⚠️ [webView] EJS solver scripts not found in bundle")
            return nil
        }
        let bridgeCode =
            "var meriyah = (typeof lib !== 'undefined' && lib.meriyah) || undefined; "
            + "var astring = (typeof lib !== 'undefined' && lib.astring) || undefined;"
        return [
            WKUserScript(source: libCode, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(source: bridgeCode, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(source: coreCode, injectionTime: .atDocumentStart, forMainFrameOnly: true),
        ]
    }

    // MARK: - Private helpers

    private func finishWithURL(_ url: URL, poToken: String?) {
        // Store the pot= token as a separate property so callers can read it from
        // `extractedPoToken` after `extractHLSURL` returns. Previously the pot was
        // baked into the manifest URL path (/pot/<token>), which is not a valid CDN
        // path and would cause a 404 on manifest fetch. The URL is passed unchanged.
        extractedPoToken = (poToken?.isEmpty == false) ? poToken : nil
        if let pot = poToken, !pot.isEmpty {
            extractLog.notice("[webView] pot= token extracted (\(pot.count) chars) — stored in extractedPoToken")
        }
        finish(url: url)
    }

    /// Abandons the in-flight extraction (e.g. VISIONOS HLS is already playing) so the
    /// hidden WKWebView stops loading YouTube instead of running to its 40 s timeout.
    func cancelCurrentExtraction() {
        finish(url: nil)
    }

    private func finish(url: URL?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        currentExtractionVideoId = nil
        // Capture and immediately nil the continuation so the cancelled timeout
        // task (which wakes after CancellationError swallowed by try?) cannot
        // double-resume it when it calls finish(url: nil).
        let pendingContinuation = continuation
        continuation = nil
        // Fan out to all extra waiters registered via awaitCurrentExtraction().
        let extras = extraContinuations
        extraContinuations.removeAll()
        for c in extras { c.resume(returning: url) }

        guard let url, let pendingContinuation else {
            // Either nil URL (timeout/error) or already resumed — just clean up.
            pendingContinuation?.resume(returning: Optional<URL>.none)
            // fix17: Keep WKWebView alive for the next extraction. stopLoading() stops the
            // current page load; the next extractHLSURL call will navigate via wv.load(request).
            // The WebContent process (JIT cache) and IndexedDB (BotGuard token) persist.
            webView?.stopLoading()
            return
        }

        extractLog.notice(
            "✅ [webView] hlsManifestUrl extracted url=\(String(url.absoluteString.prefix(200)) as NSString)")

        // Sync youtube.com session cookies from WKWebView's httpCookieStore into
        // HTTPCookieStorage.shared NOW (page-load cookies are already set by the time
        // the player makes its /player call — no need to wait for video playback).
        // The proxy loader will attach these cookies to googlevideo.com segment requests
        // so the CDN can validate the /bui/ token against VISITOR_INFO1_LIVE.
        let capturedURL = url
        // fixNSolver: Capture extractedNSolver at the moment finishWithURL is called.
        // A concurrent serialExtract call (e.g. VideoCardView prewarming) can call
        // extractHLSURL between now and when the cookie-sync Task runs, which resets
        // extractedNSolver = nil. Restoring the snapshot just before resuming the
        // continuation guarantees that racePathB / exhaustiveRetry reads the correct
        // value when they wake up on the main actor right after the resume.
        let capturedNSolver = extractedNSolver
        Task { @MainActor [weak self] in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let gvCount = cookies.filter { $0.domain.contains("googlevideo") }.count
                    let names = cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: " ")
                    extractLog.notice(
                        "⚠️ [webView] syncing \(cookies.count) cookies (\(gvCount) googlevideo): \(names as NSString)")
                    for cookie in cookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                    cont.resume()
                }
            }
            guard let self else { return }
            // Restore the nSolver snapshot so callers reading extractedNSolver immediately
            // after the continuation resumes always see the value that was valid for this URL.
            // Only restore if a newer extraction hasn't already set a different solver.
            if self.extractedNSolver == nil, let capturedNSolver {
                self.extractedNSolver = capturedNSolver
                extractLog.notice(
                    "[webView/fixNSolver] nSolver snapshot restored before resume: \(capturedNSolver.unsolved as NSString) → \(capturedNSolver.solved as NSString)"
                )
            }
            // fix17: Keep WKWebView alive — don't nil it out on success.
            // The persistent WKWebView is immediately ready for the next extraction.
            self.webView?.stopLoading()
            pendingContinuation.resume(returning: capturedURL)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension YouTubeWebViewHLSExtractor: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "hlsExtractor" else { return }

        // Message is now a JSON object: { hlsManifestUrl, poToken, source, unsolvedN, solvedN }
        var hlsURLString: String?
        var poToken: String?
        var urlSource = "unknown"
        var unsolvedNValue: String? = nil
        var solvedNValue: String? = nil
        var playerIDValue: String? = nil

        if let body = message.body as? String {
            // Try to parse as JSON first (new format)
            if let data = body.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                // Consent-wall detection message: SOCS cookie pre-seeding did not work.
                if let consentWall = json["consentWallDetected"] as? Bool, consentWall {
                    extractLog.warning(
                        "⚠️ [webView/HLS] consent wall detected — SOCS cookie bypass did not prevent EU GDPR dialog; hlsManifestUrl will not arrive"
                    )
                    return
                }
                hlsURLString = json["hlsManifestUrl"] as? String
                poToken = json["poToken"] as? String
                urlSource = (json["source"] as? String) ?? "unknown"
                unsolvedNValue = json["unsolvedN"] as? String
                solvedNValue = json["solvedN"] as? String
                playerIDValue = json["playerID"] as? String
                // fix29: Reject stale JS callbacks from a previous page. When wv.load()
                // switches to a new video, any in-flight XHR/fetch callbacks from the
                // old page may fire after `currentExtractionVideoId` has changed. The
                // JS embeds the page's own v= parameter in every message so we can
                // verify the callback belongs to the current extraction.
                if let msgVid = json["videoId"] as? String,
                    let curVid = currentExtractionVideoId,
                    msgVid != curVid
                {
                    extractLog.warning(
                        "⚠️ [webView/fix29] stale JS callback: videoId=\(msgVid as NSString) != current=\(curVid as NSString) — ignoring"
                    )
                    return
                }
            } else {
                // Fallback: raw URL string (old format)
                hlsURLString = body
            }
        }

        guard let urlString = hlsURLString,
            let url = URL(string: urlString),
            urlString.contains("googlevideo.com") || urlString.contains("manifest")
        else {
            return
        }

        extractLog.notice("⚠️ [webView] URL captured source=\(urlSource as NSString)")

        // If the JS interceptor already solved the n-challenge, use it directly.
        if let u = unsolvedNValue, let s = solvedNValue, u != s {
            extractedNSolver = (unsolved: u, solved: s)
            extractLog.notice("✅ [webView] n-challenge solved in JS: \(u as NSString) → \(s as NSString)")
            finishWithURL(url, poToken: poToken)
            return
        }

        // No n-challenge found or player ID not available — proceed without n-rewrite.
        // The in-JS solveNFromPlayerJS above now receives playerID directly (rather than
        // scanning <script> elements in the main frame, which always failed in our embed
        // context), so solvedN should be non-nil for any video that has an n-challenge.
        // If it is still nil here, the JSC Swift fallback (solveNChallengeViaNode) was
        // removed because: (a) it ran the exact same EJS solve via a new JSContext on
        // every extraction — visible as the top energy hotspot in Apple's 4.8 report;
        // (b) the in-JS path now handles it reliably; (c) the Swift path provided no
        // additional capability. Proceed to finishWithURL — if n was not solved the HLS
        // proxy will deliver the playlist with the unsolved n; the CDN may throttle but
        // the video will still play.
        if let u = unsolvedNValue {
            extractedNSolver = nil
            extractLog.notice("⚠️ [webView] n NOT solved (no playerID available): unsolvedN=\(u as NSString)")
        } else {
            extractedNSolver = nil
            extractLog.notice("⚠️ [webView] no n-challenge found in HLS manifest")
        }
        finishWithURL(url, poToken: poToken)
    }
}

// MARK: - WKNavigationDelegate

extension YouTubeWebViewHLSExtractor: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        // fix17: Ignore NSURLErrorCancelled (-999) — these fire when stopLoading() is called
        // between sequential extractions on the reused WKWebView.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        extractLog.error("❌ [webView] navigation failed: \(error.localizedDescription as NSString)")
        finish(url: Optional<URL>.none)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // fix17: Ignore NSURLErrorCancelled (-999) — these fire when stopLoading() is called
        // between sequential extractions on the reused WKWebView.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        extractLog.error("❌ [webView] provisional navigation failed: \(error.localizedDescription as NSString)")
        finish(url: Optional<URL>.none)
    }
}

#endif  // canImport(WebKit)
