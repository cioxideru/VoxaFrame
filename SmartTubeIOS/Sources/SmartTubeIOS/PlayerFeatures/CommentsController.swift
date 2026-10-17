import Foundation
import SmartTubeIOSCore

// MARK: - Comments
//
// Used by PlaybackViewModel. Fetches top-level comments via InnerTubeAPI for one video at a time;
// `videoId` is supplied per call.

/// Fetches and caches top-level comments for the active video.
@MainActor
@Observable
final class CommentsController {

    private(set) var comments: [Comment] = []
    private(set) var isLoading = false
    /// The video `comments` belong to, or are loading for.
    private(set) var videoId: String?
    /// Incremented per request; a response is applied only while its request is the latest.
    @ObservationIgnored private var generation = 0

    private let fetch: (String) async throws -> [Comment]
    private let logError: (String) -> Void

    convenience init(api: InnerTubeAPI, logError: @escaping (String) -> Void = { _ in }) {
        self.init(fetch: { try await api.fetchComments(videoId: $0) }, logError: logError)
    }

    init(fetch: @escaping (String) async throws -> [Comment], logError: @escaping (String) -> Void = { _ in }) {
        self.fetch = fetch
        self.logError = logError
    }

    /// Fetches top-level comments for `videoId`. No-op while that video's list is loaded or in flight
    /// (an empty list is fetched again). Another video clears the list; only the latest request's
    /// response is applied, even when an older one is for the same video (A → B → A).
    func load(videoId: String) {
        if videoId == self.videoId, isLoading || !comments.isEmpty { return }
        self.videoId = videoId
        comments = []
        isLoading = true
        generation += 1
        let request = generation
        Task {
            var fetched: [Comment] = []
            do {
                fetched = try await fetch(videoId)
            } catch {
                logError("fetchComments failed: \(String(describing: error))")
            }
            // A newer load owns the state now.
            guard request == generation else { return }
            comments = fetched
            isLoading = false
        }
    }
}
