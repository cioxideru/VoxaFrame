import AVFoundation
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ShortsPlayerView
//
// Full-screen vertical-swipe player for YouTube Shorts.
// Swipe up advances to the next short; swipe down goes to the previous one.
//
// The passive video surface and controls share one SwiftUI swipe gesture.

public struct ShortsPlayerView: View {
    public let startIndex: Int
    @State var window: ShortsFeedWindow
    @State var vm: PlaybackViewModel
    var videos: [Video] { window.videos }
    var currentIndex: Int { window.currentIndex }
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(SettingsStore.self) var store
    @Environment(AuthService.self) var authService
    #if os(iOS)
    /// The regular player. Stopped when Shorts open so only one AVPlayer plays and owns
    /// the remote commands.
    @Environment(PlayerStateStore.self) var playerState
    #endif
    @State var slideOffset: CGFloat = 0
    @GestureState var isDragging = false
    @State var containerHeight: CGFloat = 0
    @State var isTransitioning = false
    @State var transitionTask: Task<Void, Never>?
    @State var isFetchingMore = false
    @State var fetchMoreTask: Task<Void, Never>?
    @State var isMuted = false
    @State var showAudioTrackPicker = false
    @State var showSpeedPicker = false
    @State var nextPageToken: String?
    @State var hasLoadedFeed = false
    /// True while the app is backgrounded — guards onDisappear from calling stop()
    /// when iOS fires it as a side-effect of backgrounding rather than navigation.
    @State var isInBackground = false
    let api: InnerTubeAPI

    public init(videos: [Video], startIndex: Int = 0, api: InnerTubeAPI) {
        self.startIndex = startIndex
        self.api = api
        self._window = State(initialValue: ShortsFeedWindow(videos: videos, startIndex: startIndex))
        self._vm = State(initialValue: PlaybackViewModel(api: api, isShortsPlayer: true))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                #if os(iOS) || os(tvOS)
                // The video surface is passive; gestures belong to the layer above it.
                PlayerAVLayerView(
                    player: vm.player,
                    videoGravity: store.settings.videoGravityMode == .fill ? .resizeAspectFill : .resizeAspect
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                #else
                Color.black.ignoresSafeArea()
                #endif

                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)
                        if let msg = vm.retryStatusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.3), value: vm.retryStatusMessage)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: vm.isLoading)
                }

                // Stats for Nerds overlay (toggled by two-finger tap)
                if vm.statsForNerdsVisible {
                    StatsForNerdsOverlay(snapshot: vm.statsSnapshot)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: vm.statsForNerdsVisible)
                }
            }
            .offset(y: slideOffset)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                containerHeight = $0
            }
            .background(Color.black.ignoresSafeArea())
            #if os(iOS)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !vm.isLoading, vm.error == nil else { return }
                vm.togglePlayPause()
            }
            // Keep navigation below the overlay so it cannot cancel the slider's drag.
            .simultaneousGesture(shortsSwipeGesture)
            .onChange(of: isDragging) { _, dragging in
                guard !dragging, !isTransitioning else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
            }
            #endif
            #if os(tvOS)
            .onPlayPauseCommand { vm.togglePlayPause() }
            // Siri Remote D-pad: up/down navigate prev/next short.
            .onMoveCommand { direction in
                guard !isTransitioning, !showAudioTrackPicker, !showSpeedPicker else { return }
                switch direction {
                case .up:
                    if let next = ShortsNavigation.targetIndex(
                        vertical: -100, horizontal: 0, current: currentIndex, count: videos.count)
                    {
                        performVerticalTransition(direction: -1) { goTo(next) }
                    } else {
                        loadMoreIfNeeded(advanceWhenReady: true)
                    }
                case .down:
                    if let prev = ShortsNavigation.targetIndex(
                        vertical: 100, horizontal: 0, current: currentIndex, count: videos.count)
                    {
                        performVerticalTransition(direction: 1) { goTo(prev) }
                    } else {
                        loadMoreAtStart()
                    }
                default:
                    vm.toggleControls()
                }
            }
            #endif
            // Keep controls and accessibility outside the moving video surface.
            .overlay {
                shortsOverlay
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.shortsControlsOverlay)
            }
            .overlay {
                if let err = vm.error {
                    VStack(spacing: 12) {
                        Text(err.localizedDescription)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier(AccessibilityID.shortsErrorBanner)
                        Button("Retry") { vm.retryLoad() }
                            .buttonStyle(.vfProminent)
                            .accessibilityIdentifier(AccessibilityID.shortsRetryButton)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isFetchingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(12)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                        .padding(.bottom, 60)
                        .padding(.trailing, 20)
                        .transition(.opacity)
                }
            }
            .overlay {
                if showAudioTrackPicker {
                    PlayerAudioTrackPicker(vm: vm, showAudioTrackPicker: $showAudioTrackPicker)
                }
                if showSpeedPicker {
                    PlayerSpeedPicker(vm: vm, showSpeedPicker: $showSpeedPicker)
                }
            }
            #if DEBUG
            .overlay(alignment: .top) {
                if ShortsPlaybackUITestFixture.baseURL != nil {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text(preloadTestStatus)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier(AccessibilityID.shortsPreloadStatus)
                    }
                    .allowsHitTesting(false)
                }
            }
            #endif
            #if os(iOS)
            .navigationBarHidden(true)
            .statusBarHidden(true)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .onAppear {
                #if os(iOS)
                if playerState.presentation != .hidden { playerState.stop() }
                #endif
                vm.onPlaybackEnd = { handleShortEnded() }
                vm.updateAuthToken(authService.accessToken)
                vm.updateSAPISID(authService.sapisid)
                guard videos.indices.contains(currentIndex) else { return }
                if vm.currentVideoId == videos[currentIndex].id {
                    if vm.wasPlayingBeforeSuspend { vm.resume() }
                } else {
                    loadVideo(at: currentIndex)
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
                    vm.showControls()
                    vm.cancelControlsHide()
                }
            }
            .onDisappear {
                guard !isInBackground else { return }
                fetchMoreTask?.cancel()
                fetchMoreTask = nil
                isFetchingMore = false
                transitionTask?.cancel()
                transitionTask = nil
                isTransitioning = false
                slideOffset = 0
                vm.stop()
            }
            .onChange(of: authService.sessionGeneration) { _, _ in
                fetchMoreTask?.cancel()
                transitionTask?.cancel()
                vm.stop()
                dismiss()
            }
            .onChange(of: vm.isPlaying) { _, playing in
                if playing { preloadNextShort() }
            }
            .onChange(of: vm.isLoading) { _, loading in
                if !loading { preloadNextShort() }
            }
            .onChange(of: ShortsStreamPreference(settings: store.settings.shortsPlaybackSettings)) { _, _ in
                vm.updateSettings(store.settings)
                preloadNextShort()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    isInBackground = true
                    vm.handleBackground()
                case .active:
                    isInBackground = false
                    vm.handleForeground()
                    preloadNextShort()
                default:
                    break
                }
            }
        }  // NavigationStack
    }

    #if DEBUG
    private var preloadTestStatus: String {
        let next = vm.shortsPreloader?.prepared?.item
        let queued = (vm.player.currentItem == nil ? 0 : 1) + (next == nil ? 0 : 1)
        let buffered = next?.loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds } ?? 0
        return "id=\(vm.currentVideoId ?? "none") playing=\(vm.isPlaying && vm.currentTime > 0) "
            + "ms=\(vm.timeToPlayMs) queue=\(queued) buffered=\(Int(buffered * 1000)) "
            + "rate=\(vm.player.rate) time=\(vm.currentTime) native=\(vm.player.currentTime().seconds) "
            + "voiceRate=\(vm.voiceOver.testPlaybackRate) voiceTime=\(vm.voiceOver.testPlaybackTime) "
            + "control=\(vm.player.timeControlStatus.rawValue) "
            + "retained=\(videos.count) \(vm.cacheStatusSummary)"
    }
    #endif

}
