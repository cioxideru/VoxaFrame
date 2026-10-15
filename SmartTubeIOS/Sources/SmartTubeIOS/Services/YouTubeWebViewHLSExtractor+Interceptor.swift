#if canImport(WebKit)
import WebKit

extension YouTubeWebViewHLSExtractor {
    // MARK: - JavaScript Interceptor

    /// Injected at document-start. Intercepts the YouTube player's internal API call,
    /// extracts `hlsManifestUrl`, and solves the HLS-specific n-challenge before sending to Swift.
    ///
    /// N-challenge strategy:
    ///   1. `tryExtractHLS` fires when the YouTube player API response arrives (~2.5 s).
    ///   2. An async IIFE immediately fetches the HLS master manifest (same URL, same origin,
    ///      usually CORS-allowed from youtube.com → manifest.googlevideo.com) to find the
    ///      per-quality variant URL which contains `/n/{HLS_unsolved}/` in its path.
    ///   3. It then fetches the player JS (loaded in the page; usually a cache hit in WKWebView)
    ///      and uses yt-dlp-style regex patterns to locate the n-solver function stored in an
    ///      array inside the minified player code.
    ///   4. The solver is extracted via bracket-balanced parsing (handles commas in fn bodies),
    ///      evaluated, and called with the HLS unsolved n-value to produce the solved n.
    ///   5. The mapping (unsolvedHLS → solvedHLS) is sent to Swift so `YTHLSProxyLoader` can
    ///      rewrite all `/n/unsolved/` occurrences in the M3U8 playlist text before AVPlayer
    ///      reads it — making CDN segment requests return HTTP 200 instead of 403.
    ///   6. A 9-second fallback timer fires if the async chain fails or times out, sending
    ///      whatever state is available (nil if player JS extraction failed).
    static let interceptorJS: String = #"""
        (function() {
            'use strict';

            // Detect consent wall at document-start and report to native.
            // If the SOCS=CAI cookie pre-seeding failed (e.g. the cookie was not accepted
            // by WKWebView before the first request), YouTube redirects EU users to
            // consent.youtube.com or shows a GDPR bump on the page itself.
            // Native Swift logs a warning so EU timeout failures can be diagnosed.
            (function checkConsentWall() {
                try {
                    var h = document.location.hostname;
                    if (h === 'consent.youtube.com' ||
                        document.querySelector('[data-view-name="VIEW_NAME_CONSENT_BUMP"]') ||
                        document.querySelector('.HEBJsc')) {
                        window.webkit.messageHandlers.hlsExtractor.postMessage(
                            JSON.stringify({ consentWallDetected: true, timestamp: Date.now() })
                        );
                    }
                } catch(e) {}
            })();

            var sentFinalURL = false;
            // Set to true as soon as tryExtractHLS starts its async resolution,
            // to suppress xhrManifest/fetchManifest fallbacks from firing.
            var hlsExtractionStarted = false;

            function sendHLSURL(hlsUrl, poToken, source, unsolvedN, solvedN, playerID, capturedPageVideoId) {
                if (sentFinalURL) return;
                sentFinalURL = true;
                // fix29: Include the page's own videoId so Swift can reject stale JS
                // callbacks that fire after wv.load() switches to a new video. Without
                // this check, a pending XHR or fetch .then() from the PREVIOUS page can
                // deliver the wrong video's HLS URL into the current extraction.
                // fix29b: Prefer capturedPageVideoId (read at request setup time) over
                // window.location.href. Stale async callbacks fire AFTER wv navigates to
                // the new page, so window.location.href already shows the NEW video's ID —
                // breaking fix29's guard. Capturing at open()/fetch() call time preserves
                // the correct ID regardless of subsequent page navigation.
                var vid = capturedPageVideoId;
                if (!vid) {
                    try {
                        var m = window.location.href.match(/[?&]v=([^&]+)/);
                        vid = m ? m[1] : null;
                    } catch(e) {}
                }
                window.webkit.messageHandlers.hlsExtractor.postMessage(
                    JSON.stringify({
                        hlsManifestUrl: hlsUrl,
                        videoId:        vid,
                        poToken:        poToken   || null,
                        source:         source    || 'unknown',
                        unsolvedN:      unsolvedN || null,
                        solvedN:        solvedN   || null,
                        playerID:       playerID  || null
                    })
                );
            }

            function isManifestVariantURL(url) {
                var s = url ? url.toString() : '';
                return s.indexOf('manifest.googlevideo.com') !== -1 &&
                       (s.indexOf('hls_variant') !== -1 || s.indexOf('hls_manifest') !== -1);
            }

            function isPlayerURL(url) {
                return url && url.toString().indexOf('youtubei/v1/player') !== -1;
            }

            // ── N-solver extraction from player JS ────────────────────────────────────────
            // Extracts the function at `arrIdx` from the array `arrName` in `jsText`.
            // Uses bracket-balanced parsing so commas inside function bodies don't split incorrectly.
            function extractFnFromJSArray(jsText, arrName, arrIdx) {
                var safe = arrName.replace(/[$]/g, '\\$');
                var decl = new RegExp('var\\s+' + safe + '\\s*=\\s*\\[');
                var di   = jsText.search(decl);
                if (di < 0) return null;

                var ob = jsText.indexOf('[', di);
                if (ob < 0) return null;

                var depth = 1, i = ob + 1, eStart = ob + 1, eIdx = 0;
                while (i < jsText.length && depth > 0) {
                    var ch = jsText[i];
                    if (ch === '[' || ch === '{' || ch === '(') {
                        depth++;
                    } else if (ch === ']' || ch === '}' || ch === ')') {
                        depth--;
                        if (depth === 0) {
                            if (eIdx === arrIdx) return jsText.slice(eStart, i).trim();
                            break;
                        }
                    } else if ((ch === '"' || ch === "'" || ch === '`') && depth === 1) {
                        var q = ch; i++;
                        while (i < jsText.length && jsText[i] !== q) {
                            if (jsText[i] === '\\') i++;
                            i++;
                        }
                    } else if (ch === ',' && depth === 1) {
                        if (eIdx === arrIdx) return jsText.slice(eStart, i).trim();
                        eIdx++;
                        eStart = i + 1;
                    }
                    i++;
                }
                return null;
            }

            // Downloads the main player JS and uses the bundled EJS AST-based solver (jsc)
            // to solve `unsolvedN`. Returns the solved string, or null on failure.
            // `jsc` is defined by the solver WKUserScripts injected before this script.
            // knownPlayerID: pass the playerID already extracted from the HLS URL so we
            // skip the script-element discovery step. That step searches the MAIN frame for
            // a <script src="...player_ias..."> tag — it always fails in our embed context
            // because the player script lives inside the cross-origin YouTube iframe, not
            // in the example.com wrapper document. Passing knownPlayerID directly makes the
            // in-JS solve succeed reliably, eliminating the need for the Swift JSC fallback
            // (solveNChallengeViaNode) that was previously the only path that ever worked.
            async function solveNFromPlayerJS(unsolvedN, knownPlayerID) {
                try {
                    // jsc must be available from the EJS solver scripts injected at document-start
                    if (typeof jsc !== 'function') return null;

                    // Use the player ID passed from the caller (already in the HLS URL) rather
                    // than searching <script> tags — that search always fails in our embed context
                    // since the player script is inside the cross-origin YouTube iframe.
                    var pid = knownPlayerID;
                    if (!pid) {
                        // Fallback: try the script-element search (works on a real YouTube page)
                        var playerSrc = null;
                        var scripts = document.querySelectorAll('script[src]');
                        for (var si = 0; si < scripts.length; si++) {
                            if (scripts[si].src && scripts[si].src.indexOf('player_ias') > -1) {
                                playerSrc = scripts[si].src;
                                break;
                            }
                        }
                        if (!playerSrc) return null;
                        var pidMatch = playerSrc.match(/\/player\/([a-f0-9]+)\//);
                        if (!pidMatch) return null;
                        pid = pidMatch[1];
                    }

                    // Build the main-variant URL (player_es6) from the player ID.
                    // yt-dlp forces the 'main' variant (player_es6.vflset/en_US/base.js)
                    // because only that variant contains the n-solver function.
                    var mainUrl = 'https://www.youtube.com/s/player/' + pid +
                                  '/player_es6.vflset/en_US/base.js';

                    // Fetch with cache:default so WKWebView serves from cache if available,
                    // or fetches from network (~2.5 MB) on first call.
                    var jsResp = await origFetch.call(window, mainUrl, {cache: 'default'});
                    if (!jsResp.ok) return null;
                    var jsText = await jsResp.text();

                    // Run the EJS AST-based solver. This parses the player JS, locates the
                    // n-solver function structurally, calls it, and returns the solved value.
                    var solverInput = {
                        type: 'player',
                        player: jsText,
                        requests: [{type: 'n', challenges: [unsolvedN]}]
                    };
                    var result = jsc(solverInput);
                    if (result && result.type === 'result' &&
                        result.responses && result.responses.length > 0) {
                        var resp = result.responses[0];
                        if (resp.type === 'result' && resp.data) {
                            var solved = resp.data[unsolvedN];
                            return (typeof solved === 'string' && solved !== unsolvedN) ? solved : null;
                        }
                    }
                    return null;
                } catch(e) {
                    return null;
                }
            }

            // ── Main extraction ───────────────────────────────────────────────────────────
            function tryExtractHLS(responseData, requestBodyStr, capturedPageVideoId) {
                if (sentFinalURL || hlsExtractionStarted) return false;
                try {
                    var obj = (typeof responseData === 'string') ?
                              JSON.parse(responseData) : responseData;
                    if (!obj || !obj.streamingData || !obj.streamingData.hlsManifestUrl)
                        return false;

                    var hlsUrl  = obj.streamingData.hlsManifestUrl;
                    var poToken = null;
                    try {
                        if (requestBodyStr) {
                            var rq = JSON.parse(requestBodyStr);
                            if (rq && rq.serviceIntegrityDimensions &&
                                rq.serviceIntegrityDimensions.poToken)
                                poToken = rq.serviceIntegrityDimensions.poToken;
                        }
                    } catch(e) {}

                    hlsExtractionStarted = true;

                    // Extract player ID from multiple sources (in priority order).
                    // Sent to Swift so it can run the EJS solver via Node.js as a fallback.
                    var playerID = null;
                    try {
                        // Method 1: script[src] with any /player/ path segment
                        var piScripts = document.querySelectorAll('script[src]');
                        for (var psi = 0; psi < piScripts.length; psi++) {
                            var pSrc = piScripts[psi].src || piScripts[psi].getAttribute('src') || '';
                            if (pSrc.indexOf('/player/') > -1) {
                                var pidM = pSrc.match(/\/player\/([a-f0-9]+)\//);
                                if (pidM) { playerID = pidM[1]; break; }
                            }
                        }
                        // Method 2: ytcfg.get('PLAYER_JS_URL')
                        if (!playerID && window.ytcfg && typeof window.ytcfg.get === 'function') {
                            var pjsUrl = window.ytcfg.get('PLAYER_JS_URL') ||
                                         window.ytcfg.get('jsUrl') || '';
                            if (pjsUrl) {
                                var pm2 = pjsUrl.match(/\/player\/([a-f0-9]+)\//);
                                if (pm2) playerID = pm2[1];
                            }
                        }
                        // Method 3: Scan page HTML for the IAS player URL pattern (always present)
                        if (!playerID) {
                            var pageHtml = document.documentElement.innerHTML || '';
                            var pm3 = pageHtml.match(/\/s\/player\/([a-f0-9]{8})\/player_ias/);
                            if (pm3) playerID = pm3[1];
                        }
                    } catch(e) {}

                    // Async phase: fetch master manifest → extract HLS n-value → solve it
                    (async function() {
                        var hlsN = null, solvedN = null;

                        // Fallback timer: if async chain takes >20 s, send whatever we have.
                        var fallbackTimer = setTimeout(function() {
                            sendHLSURL(hlsUrl, poToken, 'apiResponse', hlsN, solvedN, playerID, capturedPageVideoId);
                        }, 20000);

                        try {
                            // Step 1: Fetch the HLS master manifest to find a per-quality
                            // playlist URL containing /n/{hlsN}/ in the path.
                            var mResp = await origFetch.call(window, hlsUrl, {credentials: 'include'});
                            var mText = await mResp.text();
                            // Per-quality playlist URLs embed the HLS n-value as a path segment
                            var nm = mText.match(/\/n\/([A-Za-z0-9_-]{10,})\//);
                            if (nm) hlsN = nm[1];
                        } catch(e) {}

                        try {
                            // Step 2: In-JS EJS solver — pass playerID directly so it works
                            // in our embed context (script-element discovery always fails there).
                            if (hlsN && typeof jsc === 'function') solvedN = await solveNFromPlayerJS(hlsN, playerID);
                        } catch(e) {}

                        clearTimeout(fallbackTimer);
                        // Include playerID so Swift can run the Node.js solver as fallback.
                        sendHLSURL(hlsUrl, poToken, 'apiResponse', hlsN, solvedN, playerID, capturedPageVideoId);
                    })();

                    return true;
                } catch(e) {}
                return false;
            }

            // ── video.src hook (iOS/native-HLS mode fallback) ────────────────────────────
            var mediaProto  = HTMLMediaElement.prototype;
            var origSrcDesc = Object.getOwnPropertyDescriptor(mediaProto, 'src');
            if (origSrcDesc && origSrcDesc.set) {
                Object.defineProperty(mediaProto, 'src', {
                    set: function(url) {
                        if (url && typeof url === 'string' && isManifestVariantURL(url)) {
                            var pageVid = null;
                            try {
                                var m = window.location.href.match(/[?&]v=([^&]+)/);
                                pageVid = m ? m[1] : null;
                            } catch(e) {}
                            sendHLSURL(url, null, 'videoSrc', null, null, null, pageVid);
                        }
                        return origSrcDesc.set.call(this, url);
                    },
                    get: origSrcDesc.get,
                    configurable: true
                });
            }

            // ── XHR hook ──────────────────────────────────────────────────────────────────
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;

            XMLHttpRequest.prototype.open = function(method, url) {
                var urlStr = url ? url.toString() : '';
                this.__isPlayerReq   = isPlayerURL(urlStr);
                this.__isManifestReq = isManifestVariantURL(urlStr);
                if (this.__isManifestReq) this.__manifestUrl = urlStr;
                // fix29b: Capture page videoId at open() time, before any async page
                // navigation. Stale .then() callbacks read window.location.href AFTER
                // wv navigates — by then it shows the new video's ID, bypassing fix29.
                if (this.__isPlayerReq || this.__isManifestReq) {
                    try {
                        var m = window.location.href.match(/[?&]v=([^&]+)/);
                        this.__pageVideoId = m ? m[1] : null;
                    } catch(e) { this.__pageVideoId = null; }
                }
                return origOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function(body) {
                // xhrManifest fallback — only fires if player API never responded
                if (this.__isManifestReq && this.__manifestUrl && !hlsExtractionStarted)
                    sendHLSURL(this.__manifestUrl, null, 'xhrManifest', null, null, null, this.__pageVideoId);
                if (this.__isPlayerReq) {
                    var capturedBody = (typeof body === 'string') ? body : null;
                    var capturedPageVideoId = this.__pageVideoId;  // fix29b: captured at open() time
                    this.addEventListener('load', function() {
                        tryExtractHLS(this.responseText, capturedBody, capturedPageVideoId);
                    });
                }
                return origSend.apply(this, arguments);
            };

            // ── fetch hook ────────────────────────────────────────────────────────────────
            var origFetch = window.fetch;
            window.fetch = function(input, init) {
                var url = (typeof input === 'string') ? input :
                          (input && (input.url || input.href)) || '';
                var bodyStr = null;
                // fix29b: Capture page videoId at fetch() call time, before any async
                // navigation. The .then() callback fires asynchronously and may read
                // a different window.location.href if wv has navigated by then.
                var capturedPageVideoId = null;
                try {
                    var m = window.location.href.match(/[?&]v=([^&]+)/);
                    capturedPageVideoId = m ? m[1] : null;
                } catch(e) {}
                try {
                    if (isPlayerURL(url) && init && init.body)
                        bodyStr = (typeof init.body === 'string') ? init.body : null;
                } catch(e) {}

                var promise = origFetch.apply(this, arguments);
                if (isManifestVariantURL(url)) {
                    // fetchManifest fallback — only fires if player API never responded
                    if (!hlsExtractionStarted)
                        sendHLSURL(url, null, 'fetchManifest', null, null, null, capturedPageVideoId);
                } else if (isPlayerURL(url)) {
                    var capturedBody = bodyStr;
                    promise.then(function(response) {
                        return response.clone().text().then(function(text) {
                            tryExtractHLS(text, capturedBody, capturedPageVideoId);
                        });
                    }).catch(function() {});
                }
                return promise;
            };

            // ── DOMContentLoaded fallback ─────────────────────────────────────────────────
            document.addEventListener('DOMContentLoaded', function() {
                try {
                    if (window.ytInitialPlayerResponse) {
                        var vid = null;
                        try {
                            var m = window.location.href.match(/[?&]v=([^&]+)/);
                            vid = m ? m[1] : null;
                        } catch(e) {}
                        tryExtractHLS(window.ytInitialPlayerResponse, null, vid);
                    }
                } catch(e) {}
            });
        })();
        """#

}
#endif
