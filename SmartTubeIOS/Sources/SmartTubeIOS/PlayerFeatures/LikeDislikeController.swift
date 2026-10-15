import Foundation
import SmartTubeIOSCore

// MARK: - Like / Dislike
//
// Used by PlaybackViewModel. The video id and error logging are supplied per
// call so the controller needs no back-reference to its owning view model.

/// Toggles the like/dislike state for a video via InnerTubeAPI, with an
/// optimistic update that rolls back on failure.
@MainActor
@Observable
final class LikeDislikeController {

    private(set) var likeStatus: LikeStatus = .none

    private let api: InnerTubeAPI
    private let logError: (String) -> Void

    init(api: InnerTubeAPI, logError: @escaping (String) -> Void) {
        self.api = api
        self.logError = logError
    }

    /// Seeds `likeStatus` from a previously-fetched `nextInfo` without making an API call.
    func setLikeStatus(_ status: LikeStatus) {
        likeStatus = status
    }

    /// Toggles the like state for `videoId` (optimistic update; rolls back on failure).
    /// No-op if `videoId` is nil.
    func like(videoId: String?) {
        guard let videoId else { return }
        let prev = likeStatus
        likeStatus = prev == .like ? .none : .like
        Task {
            do {
                if prev == .like {
                    try await api.removeLike(videoId: videoId)
                } else {
                    try await api.like(videoId: videoId)
                }
            } catch {
                self.likeStatus = prev
                logError("like failed: \(String(describing: error))")
            }
        }
    }

    /// Toggles the dislike state for `videoId` (optimistic update; rolls back on failure).
    /// No-op if `videoId` is nil.
    func dislike(videoId: String?) {
        guard let videoId else { return }
        let prev = likeStatus
        likeStatus = prev == .dislike ? .none : .dislike
        Task {
            do {
                if prev == .dislike {
                    try await api.removeLike(videoId: videoId)
                } else {
                    try await api.dislike(videoId: videoId)
                }
            } catch {
                self.likeStatus = prev
                logError("dislike failed: \(String(describing: error))")
            }
        }
    }
}
