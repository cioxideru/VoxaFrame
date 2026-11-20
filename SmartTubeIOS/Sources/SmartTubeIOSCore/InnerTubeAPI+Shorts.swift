import Foundation
import os

private let shortsLog = Logger(subsystem: appSubsystem, category: "ShortsFeed")

/// The account and Brand Account one sequence page goes out as, read once (PLAN-0052): its `reel_watch_sequence` and
/// its title lookups carry them, and a lookup is not sent once the account or Brand Account is no longer this one.
struct ShortsAccountSnapshot: Equatable, Sendable {
    let token: String
    let pageId: String?
    /// `InnerTubeAPI.signInSession`: a refreshed token keeps it, a sign-in under another account does not.
    let signIn: Int

    /// The sign-in and Brand Account a sequence continuation is bound to (`InnerTubeAPI.shortsSequenceToken`).
    var continuationOwner: String { "\(signIn)/\(pageId ?? "")" }

    /// The snapshot's Brand Account, fixed for `postTV(brandAccount:)`.
    var brandAccount: ActiveChannel {
        let channel = ActiveChannel()
        channel.set(pageId: pageId)
        return channel
    }
}

/// The one deadline of a sequence page's title lookups (PLAN-0052): `wait()` returns once it has passed (or when
/// cancelled) and `hasPassed()` tells at once, both from the same absolute instant.
struct ShortsMetadataDeadline: Sendable {
    let wait: @Sendable () async -> Void
    let hasPassed: @Sendable () -> Bool

    /// `timeout` from now.
    static func after(_ timeout: Duration) -> ShortsMetadataDeadline {
        let instant = ContinuousClock.now + timeout
        return ShortsMetadataDeadline(
            wait: {
                do {
                    try await Task.sleep(until: instant, clock: .continuous)
                } catch {
                    return  // Cancelled: every lookup has answered.
                }
            },
            hasPassed: { ContinuousClock.now >= instant })
    }
}

// MARK: - Full-screen Shorts feed

extension InnerTubeAPI {

    /// Prefix of a continuation at the feed's end once it follows the account's `reel/reel_watch_sequence`. Alone it
    /// asks only for the sequence's first page; `reel:srch:` continues the signed-out search a refusal moved the end
    /// to; any other is the sequence's own (`shortsSequenceToken`).
    static let shortsSequencePrefix = "reel:"

    /// The sequence's `continuation` bound to the sign-in and Brand Account that got its page
    /// (`<sign-in>/<page ID, empty for the primary account>`): no other one sends it on. It holds no token.
    static func shortsSequenceToken(_ continuation: String, for account: ShortsAccountSnapshot) -> String {
        shortsSequencePrefix + account.continuationOwner + ":" + continuation
    }

    /// One shared wait for the title and channel lookups of a sequence page: a slow lookup must not hold the page.
    public static let shortsMetadataTimeout: Duration = .seconds(4)
    /// At most this many title lookups run at once; the others wait for a free slot within the same deadline.
    static let shortsMetadataConcurrency = 6

    /// The full-screen Shorts player's next page (PLAN-0052). The account is read once, and that snapshot picks the
    /// page's source. At the end of a signed-in feed that starts at `seedVideoId`, any token but a `reel:` one starts
    /// the account's own Shorts order from `reel/reel_watch_sequence`, sent with its Bearer token and Brand Account; a
    /// `reel:` token continues it, only for the sign-in and Brand Account that got it. Its Shorts get their title and
    /// channel within `metadataTimeout`. When YouTube refuses the sequence, the end goes on with the signed-out search,
    /// sent without cookies, its tokens still `reel:` ones. A bare `reel:` that cannot start the sequence gets an empty
    /// page.
    ///
    /// Every other page, and every `prepending` one, comes from the presentation's source as before PLAN-0052:
    /// `fetchShorts()` / `fetchShortsMore(continuationToken:)`, except that a `srch:` token continues the signed-out
    /// search whoever is signed in now, so a feed that began before the account's token arrived can still load back.
    public func fetchShortsFeed(
        seedVideoId: String?, continuationToken: String?, prepending: Bool = false,
        metadataTimeout: Duration = shortsMetadataTimeout
    ) async throws -> VideoGroup {
        let account = shortsAccountSnapshot
        let route = continuationToken.flatMap {
            $0.hasPrefix(Self.shortsSequencePrefix) ? $0.dropFirst(Self.shortsSequencePrefix.count) : nil
        }
        if let route, route.hasPrefix(Self.shortsSearchPrefix) {
            return Self.followingSequence(
                try await fetchAnonymousShorts(
                    continuationToken: String(route.dropFirst(Self.shortsSearchPrefix.count)), useCookies: false))
        }
        if let route, !route.isEmpty {
            guard let account else { throw APIError.notAuthenticated }
            guard let separator = route.firstIndex(of: ":"), route[..<separator] == account.continuationOwner else {
                shortsLog.notice("reel_watch_sequence continuation of another sign-in or channel not sent")
                throw APIError.unavailable("Reload Shorts after changing accounts.")
            }
            return try await fetchAccountShortsSequence(
                seedVideoId: nil, continuation: String(route[route.index(after: separator)...]), as: account,
                metadataTimeout: metadataTimeout)
        }
        if !prepending, let seedVideoId, let account, Self.mayFollowShortsSequence {
            return try await fetchAccountShortsSequence(
                seedVideoId: seedVideoId, continuation: nil, as: account, metadataTimeout: metadataTimeout)
        }
        if route != nil { return VideoGroup(title: "Shorts") }  // The presentation's source ended: never restarted.
        if let continuationToken, continuationToken.hasPrefix(Self.shortsSearchPrefix) {
            return try await fetchAnonymousShorts(
                continuationToken: String(continuationToken.dropFirst(Self.shortsSearchPrefix.count)))
        }
        if let continuationToken { return try await fetchShortsMore(continuationToken: continuationToken) }
        return try await fetchShorts()
    }

    /// The DEBUG Home pagination fixture serves every Shorts page itself.
    private static var mayFollowShortsSequence: Bool {
        #if DEBUG
        return !HomePaginationUITestFixture.isEnabled
        #else
        return true
        #endif
    }

    /// `group` with its next token marked `reel:`: the end keeps its own cursor on the search after a refusal.
    private static func followingSequence(_ group: VideoGroup) -> VideoGroup {
        var tagged = group
        tagged.nextPageToken = group.nextPageToken.map { shortsSequencePrefix + $0 }
        return tagged
    }

    /// One page of the account's sequence, sent as `account`, or the first signed-out search page when YouTube refuses
    /// it: an HTTP or transport error, an InnerTube `error`, `logged_in=0`, or no Shorts left after parsing.
    func fetchAccountShortsSequence(
        seedVideoId: String?, continuation: String?, as account: ShortsAccountSnapshot, metadataTimeout: Duration
    ) async throws -> VideoGroup {
        var body = makeBody(client: tvClientContext, continuationToken: continuation)
        if continuation == nil, let seedVideoId {
            body["sequenceParams"] = ShortsSequence.seedParams(videoId: seedVideoId)
        }
        let refusal: String
        do {
            let json = try await postTV(
                endpoint: "reel/reel_watch_sequence", body: body, explicitBearerToken: account.token,
                brandAccount: account.brandAccount)
            let page = ShortsSequence.parse(json)
            let loggedIn = page.isLoggedIn.map { $0 ? "1" : "0" } ?? "?"
            shortsLog.notice(
                "reel_watch_sequence: \(page.videos.count, privacy: .public) Shorts, logged_in=\(loggedIn, privacy: .public), more=\(page.continuation != nil, privacy: .public)"
            )
            if page.hasError {
                refusal = "error response"
            } else if page.isLoggedIn == false {
                refusal = "logged_in=0"
            } else if page.videos.isEmpty {
                refusal = "no Shorts"
            } else {
                let videos = await fillingShortsMetadata(page.videos, as: account, until: .after(metadataTimeout))
                return VideoGroup(
                    title: "Shorts", videos: videos,
                    nextPageToken: page.continuation.map { Self.shortsSequenceToken($0, for: account) })
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            refusal = ViewModelLogger.errorSummary(error)
        }
        shortsLog.notice(
            "reel_watch_sequence refused (\(refusal, privacy: .public)), continuing with signed-out Shorts search")
        return Self.followingSequence(try await fetchAnonymousShorts(continuationToken: nil, useCookies: false))
    }

    /// The account and Brand Account requests go out as now; nil signed out.
    var shortsAccountSnapshot: ShortsAccountSnapshot? {
        authToken.map { ShortsAccountSnapshot(token: $0, pageId: activeChannel.pageId, signIn: signInSession) }
    }

    /// `videos` with an empty title, channel name or channel ID filled from each Short's `reel/reel_item_watch`, sent
    /// as `account`. Each Short still lacking a field is looked up once, at most `shortsMetadataConcurrency` at a
    /// time, until `deadline` passes: an answer that comes after it is dropped and frees no slot, the lookups still
    /// running are cancelled, and the queued ones never start. A Short whose lookup fails or is late stays as it was,
    /// in its place; known values are never replaced.
    func fillingShortsMetadata(
        _ videos: [Video], as account: ShortsAccountSnapshot, until deadline: ShortsMetadataDeadline
    ) async -> [Video] {
        var seen = Set<String>()
        var queue = videos.filter { ShortsSequence.needsMetadata($0) && seen.insert($0.id).inserted }.map(\.id)[...]
        guard !queue.isEmpty else { return videos }
        let lookUp: @Sendable (String) async -> (String, ShortsSequence.Metadata?)? = { videoId in
            (videoId, await self.fetchShortMetadata(videoId: videoId, as: account, until: deadline))
        }
        let answers = await withTaskGroup(of: (String, ShortsSequence.Metadata?)?.self) { group in
            group.addTask {
                await deadline.wait()
                return nil  // The deadline.
            }
            var pending = queue.count
            for _ in 0..<min(Self.shortsMetadataConcurrency, queue.count) {
                let videoId = queue.removeFirst()
                group.addTask { await lookUp(videoId) }
            }
            var answers: [String: ShortsSequence.Metadata] = [:]
            // The deadline is checked again here: its timer can wake after an answer that came too late.
            while pending > 0, let next = await group.next(), let (videoId, metadata) = next, !deadline.hasPassed() {
                pending -= 1
                if let metadata { answers[videoId] = metadata }
                if let following = queue.popFirst() { group.addTask { await lookUp(following) } }
            }
            group.cancelAll()
            return answers
        }
        let filled = videos.map { video in answers[video.id].map { ShortsSequence.filling(video, with: $0) } ?? video }
        let unfilled = filled.filter(ShortsSequence.needsMetadata).count
        if unfilled > 0 {
            shortsLog.notice(
                "reel_item_watch: \(unfilled, privacy: .public) of \(videos.count, privacy: .public) Shorts without a title or channel"
            )
        }
        return filled
    }

    /// A Short's overlay title and channel, sent like its sequence (TVHTML5, Bearer, Brand Account) as `account`; nil
    /// without a request once `deadline` has passed, the lookup is cancelled or the account or Brand Account is no
    /// longer `account`, and nil when the request fails or the answer has no overlay.
    private func fetchShortMetadata(
        videoId: String, as account: ShortsAccountSnapshot, until deadline: ShortsMetadataDeadline
    ) async -> ShortsSequence.Metadata? {
        var body = makeBody(client: tvClientContext)
        body["playerRequest"] = ["videoId": videoId]
        body["params"] = ShortsSequence.metadataParams
        body["disablePlayerResponse"] = true
        // Right before the request: a queued lookup can start after the deadline or once the page is done.
        guard !deadline.hasPassed(), !Task.isCancelled, shortsAccountSnapshot == account else { return nil }
        guard
            let json = try? await postTV(
                endpoint: "reel/reel_item_watch", body: body, explicitBearerToken: account.token,
                brandAccount: account.brandAccount)
        else { return nil }
        return ShortsSequence.metadata(from: json)
    }
}
