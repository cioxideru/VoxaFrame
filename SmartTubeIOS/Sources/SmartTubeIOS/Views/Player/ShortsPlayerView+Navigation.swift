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
        guard !isTransitioning else { return }
        let transitionHeight = containerHeight
        isTransitioning = true
        withAnimation(.easeIn(duration: 0.2)) {
            slideOffset = direction * transitionHeight
        }
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            action()  // switch video, clears AVPlayer
            slideOffset = -direction * transitionHeight  // snap to opposite side (off-screen)
            withAnimation(.easeOut(duration: 0.25)) {
                slideOffset = 0  // slide new content in
            }
            try? await Task.sleep(for: .milliseconds(270))
            guard !Task.isCancelled else { return }
            isTransitioning = false
            transitionTask = nil
        }
    }

    func goTo(_ index: Int) {
        guard index >= 0, index < videos.count else { return }

        window.move(to: index)
        loadVideo(at: currentIndex)

        // Pre-fetch more Shorts when within 2 of the end.
        if currentIndex >= videos.count - 2 {
            loadMoreIfNeeded()
        }
    }

    func loadMoreIfNeeded(advanceWhenReady: Bool = false) {
        loadMore(prepending: false, advanceWhenReady: advanceWhenReady)
    }

    func loadMoreAtStart() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
        loadMore(prepending: true, advanceWhenReady: true)
    }

    private func loadMore(prepending: Bool, advanceWhenReady: Bool) {
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("--uitesting") || args.contains("--uitesting-home-pagination"),
            !isFetchingMore, !hasLoadedFeed || nextPageToken != nil
        else { return }
        isFetchingMore = true
        let session = authService.sessionGeneration
        fetchMoreTask = Task { @MainActor in
            defer { isFetchingMore = false }
            // Bound empty/duplicate pages so a swipe never drains the account's entire feed.
            for _ in 0..<InnerTubeClients.maxShortsPagesPerRequest {
                guard !Task.isCancelled, session == authService.sessionGeneration else { return }
                let token = nextPageToken
                let group: VideoGroup
                do {
                    if let token {
                        group = try await api.fetchShortsMore(continuationToken: token)
                    } else {
                        group = try await api.fetchShorts()
                    }
                } catch { return }  // Keep the token so a later swipe can retry.
                guard !Task.isCancelled, session == authService.sessionGeneration else { return }
                hasLoadedFeed = true
                nextPageToken = window.nextCursor(after: token, proposed: group.nextPageToken)
                var seen = Set(videos.map(\.id))
                let added = group.videos.filter { seen.insert($0.id).inserted }
                if !added.isEmpty {
                    if prepending {
                        let wasAtStart = currentIndex == 0
                        window.insert(added, prepending: true)
                        if advanceWhenReady, wasAtStart {
                            performVerticalTransition(direction: 1) { goTo(currentIndex - 1) }
                        }
                    } else {
                        let wasAtEnd = currentIndex == videos.count - 1
                        window.insert(added, prepending: false)
                        if advanceWhenReady, wasAtEnd {
                            performVerticalTransition(direction: -1) { goTo(currentIndex + 1) }
                        }
                    }
                    preloadNextShort()
                    return
                }
                guard nextPageToken != nil else { return }
            }
        }
    }

    /// End of a Short: replay, advance to the next Short, or freeze on the last one —
    /// never the regular player's queue/recommendation autoplay.
    func handleShortEnded() {
        guard !isTransitioning else { return }
        switch ShortsEndOfVideoDecision.decide(
            settings: store.settings, currentIndex: currentIndex, count: videos.count)
        {
        case .replay:
            vm.videoEnded = true
            vm.togglePlayPause()
        case .advance(let next):
            performVerticalTransition(direction: -1) { goTo(next) }
        case .freeze:
            vm.videoEnded = true
        }
    }

    func loadVideo(at index: Int) {
        guard videos.indices.contains(index) else { return }
        let video = videos[index]
        vm.updateSettings(store.settings)
        showAudioTrackPicker = false
        showSpeedPicker = false
        vm.load(video: video)
        vm.player.isMuted = isMuted
        vm.voiceOver.isMuted = isMuted
    }

    func preloadNextShort() {
        guard !isInBackground else { return }
        vm.preloadNextShort(videos.indices.contains(currentIndex + 1) ? videos[currentIndex + 1] : nil)
    }
}
