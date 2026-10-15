import AVFoundation
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension ShortsPlayerView {

    // MARK: - Navigation

    /// Animates the current content off-screen in `direction` (-1 = up, +1 = down),
    /// runs `action` to switch to the new video, then slides the new content in
    /// from the opposite side.
    func performVerticalTransition(direction: CGFloat, action: @escaping () -> Void) {
        let screenHeight: CGFloat = 1000
        isTransitioning = true
        withAnimation(.easeIn(duration: 0.2)) {
            slideOffset = direction * screenHeight
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            action()  // switch video, clears AVPlayer
            slideOffset = -direction * screenHeight  // snap to opposite side (off-screen)
            withAnimation(.easeOut(duration: 0.25)) {
                slideOffset = 0  // slide new content in
            }
            try? await Task.sleep(for: .milliseconds(270))
            isTransitioning = false
        }
    }

    func goTo(_ index: Int) {
        guard index >= 0, index < videos.count else { return }

        currentIndex = index
        loadVideo(at: index)

        // Pre-fetch more Shorts when within 2 of the end.
        if index >= videos.count - 2 {
            loadMoreIfNeeded()
        }
        // Pre-fetch the next 2 shorts so swiping is instant.
        let lookahead = videos[(index + 1)..<min(index + 3, videos.count)].map(\.id)
        if !lookahead.isEmpty {
            let token = authService.accessToken
            let cats = store.settings.activeSponsorCategories
            Task(priority: .background) {
                for videoId in lookahead {
                    await VideoPreloadCache.shared.prefetch(
                        videoId: videoId,
                        sponsorCategories: cats,
                        authToken: token,
                        priority: .speculative
                    )
                }
            }
        }
    }

    /// Fetches an additional batch of Shorts and appends them, deduplicating by id.
    func loadMoreIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        guard !isFetchingMore else { return }
        isFetchingMore = true
        let existingIDs = Set(videos.map(\.id))
        Task { @MainActor in
            defer { isFetchingMore = false }
            guard let group = try? await api.fetchShorts() else { return }
            let newVideos = group.videos.filter { !existingIDs.contains($0.id) }
            guard !newVideos.isEmpty else { return }
            videos.append(contentsOf: newVideos)
        }
    }

    /// Fetches a batch of Shorts, prepends them before the current video, adjusts
    /// `currentIndex` to keep the current video in place, then animates down into
    /// the last prepended video — giving the user new content above.
    func loadMoreAtStart() {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
            return
        }
        guard !isFetchingMore else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
            return
        }
        isFetchingMore = true
        // Spring back to centre while the fetch is in flight.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
        let existingIDs = Set(videos.map(\.id))
        Task { @MainActor in
            defer { isFetchingMore = false }
            guard let group = try? await api.fetchShorts() else { return }
            let newVideos = group.videos.filter { !existingIDs.contains($0.id) }
            guard !newVideos.isEmpty else { return }
            // Prepend the new videos; re-anchor currentIndex so the on-screen
            // video doesn't change, then animate down to the last prepended video.
            videos.insert(contentsOf: newVideos, at: 0)
            currentIndex += newVideos.count
            performVerticalTransition(direction: 1) { goTo(currentIndex - 1) }
        }
    }

    /// End of a Short: replay, advance to the next Short, or freeze on the last one —
    /// never the regular player's queue/recommendation autoplay.
    func handleShortEnded() {
        switch ShortsEndOfVideoDecision.decide(
            settings: store.settings, currentIndex: currentIndex, count: videos.count)
        {
        case .replay:
            vm.player.seek(to: .zero)
            vm.player.rate = Float(store.settings.playbackSpeed)
        case .advance(let next):
            performVerticalTransition(direction: -1) { goTo(next) }
        case .freeze:
            vm.videoEnded = true
        }
    }

    func loadVideo(at index: Int) {
        let video = videos[index]
        CrashlyticsLogger.setIntendedVideo(id: video.id, title: video.title)
        vm.updateSettings(store.settings)
        vm.setPlaybackSpeed(store.settings.playbackSpeed)
        vm.load(video: video)
    }
}
