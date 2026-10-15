import Foundation

/// Pure end-of-video decision for `ShortsPlayerView` — what to do when a Short
/// finishes playing (`PlaybackViewModel.onPlaybackEnd`).
///
/// Replaces `PlaybackViewModel.handlePlaybackEnd()`'s queue/related-videos autoplay
/// for Shorts: just the linear `videos` array `ShortsPlayerView` pages through via
/// `ShortsNavigation.targetIndex`. A pure function over `(settings, currentIndex, count)`.
public enum ShortsEndOfVideoDecision: Equatable {
    /// `settings.loopEnabled` is on — seek the current Short back to 0 and replay.
    case replay
    /// Advance to `videos[to]` — same path as a swipe-up (`goTo(to)`).
    case advance(to: Int)
    /// At the end of `videos` with looping off — mirror today's "exhausted"
    /// behavior (`videoEnded = true`), freeze on the last frame.
    case freeze

    /// - Parameters:
    ///   - settings: Only `settings.loopEnabled` is consulted.
    ///   - currentIndex: Index of the Short that just ended.
    ///   - count: `videos.count`.
    public static func decide(settings: AppSettings, currentIndex: Int, count: Int) -> ShortsEndOfVideoDecision {
        if settings.loopEnabled {
            return .replay
        }
        let next = currentIndex + 1
        if next < count {
            return .advance(to: next)
        }
        return .freeze
    }
}
