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
    /// With Reduce Motion a Short replaces the previous one at once instead of sliding the full height.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    #if os(tvOS)
    @FocusState var videoFocused: Bool
    @FocusState var focusedControl: String?
    #endif
    #if os(iOS)
    /// The regular player. Stopped when Shorts open so only one AVPlayer plays and owns
    /// the remote commands.
    @Environment(PlayerStateStore.self) var playerState
    /// Landscape iPhone: the control rail runs in a row.
    @Environment(\.verticalSizeClass) var verticalSizeClass
    #endif
    #if !os(tvOS)
    /// Accessibility text: the control rail folds into two rows.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
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
                    PlayerLoadingIndicator(message: vm.retryStatusMessage)
                }

                // Stats for Nerds overlay (toggled by two-finger tap)
                if vm.statsForNerdsVisible {
                    StatsForNerdsOverlay(snapshot: vm.statsSnapshot)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: vm.statsForNerdsVisible)
                }
            }
            .offset(y: slideOffset)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { size in
                containerHeight = size.height
                #if os(iOS)
                let landscape = size.width > size.height
                if vm.isLandscape != landscape {
                    vm.isLandscape = landscape
                    if vm.controlsVisible { vm.showControls() }
                }
                #endif
            }
            .background(Color.black.ignoresSafeArea())
            #if !os(tvOS)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isTransitioning, !vm.isScrubbing, !isPanelOpen else { return }
                if keepsControlsVisible { vm.showControls() } else { vm.toggleControls() }
            }
            #endif
            #if os(iOS)
            // Keep navigation below the overlay so it cannot cancel the slider's drag.
            .simultaneousGesture(shortsSwipeGesture)
            .onChange(of: isDragging) { _, dragging in
                guard !isTransitioning else { return }
                if dragging {
                    if !vm.isScrubbing, !isPanelOpen { vm.showControls() }
                } else {
                    snapBack()
                }
            }
            #endif
            #if os(tvOS)
            // With the buttons hidden, the video takes focus so remote input still reaches Shorts.
            .focusable(!showsControls)
            .focused($videoFocused)
            .onTapGesture { vm.showControls() }
            .onPlayPauseCommand {
                vm.togglePlayPause()
                vm.showControls()
            }
            // Siri Remote D-pad: up/down navigate next/prev short.
            .onMoveCommand { direction in
                guard !isTransitioning, !isPanelOpen else { return }
                switch direction {
                case .up: showNextShort()
                case .down: showPreviousShort()
                default: vm.showControls()
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
                        Image(systemName: AppSymbol.warning)
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(err.localizedDescription)
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier(AccessibilityID.shortsErrorBanner)
                        Button("Try Again") {
                            vm.retryLoad()
                            vm.showControls()
                        }
                        .buttonStyle(.vfProminent)
                        // A one-word action: its own width, never truncated by the card's measuring.
                        .fixedSize()
                        .accessibilityIdentifier(AccessibilityID.shortsRetryButton)
                    }
                    .foregroundStyle(VFColor.onMedia)
                    .padding(VFSpace.s20)
                    .vfGlass(in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    .padding()
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
            .modifier(
                ShortsOptionPanels(
                    vm: vm, showAudioTrackPicker: $showAudioTrackPicker, showSpeedPicker: $showSpeedPicker)
            )
            #if os(tvOS)
            .onExitCommand {
                if showAudioTrackPicker {
                    showAudioTrackPicker = false
                } else if showSpeedPicker {
                    showSpeedPicker = false
                } else if showsControls, !keepsControlsVisible {
                    vm.toggleControls()
                } else {
                    dismiss()
                }
            }
            #endif
            #if DEBUG
            .onChange(of: vm.settings.controlsHideTimeout) { _, _ in
                applyControlsHideTimeoutForUITesting()
            }
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
