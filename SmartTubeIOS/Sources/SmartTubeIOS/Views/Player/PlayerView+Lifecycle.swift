import AVFoundation
import AVKit
import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

let playerLifecycleLog = ViewModelLogger(category: "Player")

// MARK: - PlayerView Lifecycle
extension PlayerView {

    // MARK: - Full player body with lifecycle modifiers
    //
    // Extracted from body so the compiled symbol for `body` shrinks from ~16 KB to ~100 bytes.
    // All lifecycle wiring (onAppear, onChange, tvOS focus, navigation, alerts) lives here
    // as its own compiled function, keeping the type tree out of PlayerView.body.
    #if os(tvOS)
    // Extracted from bodyWithLifecycleModifiers to prevent Swift type-checker timeout
    // (error: "unable to type-check this expression in reasonable time").
    // Each property is a separate type-inference scope so the cumulative generic depth
    // of the modifier chain stays within the compiler threshold.
    private var tvosPlayerGestureModifiers: some View {
        playerContentView
            // When no overlay is open, the outer view is the exclusive focus target and
            // handles all remote input via onMoveCommand / onTapGesture.
            // When an overlay (more menu, quality, speed, sleep timer) is visible, focus is
            // yielded so the overlay's buttons are reachable by the Siri Remote.
            // `.focusScope` + `.prefersDefaultFocus` ensure the ZStack actively claims
            // default focus when pushed via NavigationStack, rather than waiting for the
            // focus engine to pick a child element or leaving focus on the previous screen.
            .focusScope(playerBodyNamespace)
            .prefersDefaultFocus(in: playerBodyNamespace)
            .focusable(!isAnyOverlayVisible && !isSkipToastActive)
            .focused($playerFocused)
            .modifier(
                ConditionalMoveCommand(enabled: !isAnyOverlayVisible && !isSkipToastActive) { direction in
                    playerLifecycleLog.debug(
                        "[tv] onMoveCommand dir=\(String(describing: direction)) isTransitioning=\(isTransitioning) highlighted=\(String(describing: highlightedControl))"
                    )
                    guard !isTransitioning else { return }
                    if let current = highlightedControl {
                        // Controls-nav mode: move the highlight between buttons.
                        highlightedControl = tvNextControl(from: current, direction: direction)
                        vm.showControls()
                    } else if vm.controlsVisible {
                        // Controls visible but nav not started yet.
                        // Left/right seeks directly (Siri Remote gen 1 edge-tap and D-pad seek UX);
                        // up/down enters control-navigation mode so the user can reach other buttons.
                        switch direction {
                        case .left: vm.seekRelative(seconds: -Double(store.settings.seekBackSeconds))
                        case .right: vm.seekRelative(seconds: Double(store.settings.seekForwardSeconds))
                        default:
                            highlightedControl = .playPause
                            vm.showControls()
                        }
                    } else {
                        // Controls hidden: left/right seek, up/down shows controls.
                        switch direction {
                        case .left: vm.seekRelative(seconds: -10)
                        case .right: vm.seekRelative(seconds: 10)
                        default:
                            vm.showControls()
                            highlightedControl = .playPause
                        }
                    }
                }
            )
            .onTapGesture {
                playerLifecycleLog.notice(
                    "[tv] onTapGesture (select) — isAnyOverlayVisible=\(isAnyOverlayVisible) highlighted=\(String(describing: highlightedControl)) controlsVisible=\(vm.controlsVisible)"
                )
                guard !isAnyOverlayVisible && !isSkipToastActive else { return }
                if let current = highlightedControl {
                    tvActivateControl(current)
                } else if vm.controlsVisible {
                    highlightedControl = .playPause
                    vm.showControls()
                } else {
                    vm.showControls()
                    highlightedControl = .playPause
                }
            }
            .onPlayPauseCommand { vm.togglePlayPause() }
            .onExitCommand {
                playerLifecycleLog.notice(
                    "[tv] onExitCommand — showMoreMenu=\(showMoreMenu) showQuality=\(showQualityPicker) showSpeed=\(showSpeedPicker) showSleep=\(showSleepTimerPicker) showCaption=\(showCaptionPicker) showAudio=\(showAudioTrackPicker) showDesc=\(showDescriptionSheet) showComments=\(showCommentsSheet) highlighted=\(String(describing: highlightedControl)) controlsVisible=\(vm.controlsVisible)"
                )
                // Dismiss any open overlay first — Menu/Back is the tvOS dismiss convention.
                if showMoreMenu {
                    showMoreMenu = false
                    return
                }
                if showQualityPicker {
                    showQualityPicker = false
                    return
                }
                if showSpeedPicker {
                    showSpeedPicker = false
                    return
                }
                if showSleepTimerPicker {
                    showSleepTimerPicker = false
                    return
                }
                if showCaptionPicker {
                    showCaptionPicker = false
                    return
                }
                if showAudioTrackPicker {
                    showAudioTrackPicker = false
                    return
                }
                if showDescriptionSheet {
                    showDescriptionSheet = false
                    return
                }
                if showCommentsSheet {
                    showCommentsSheet = false
                    return
                }
                if highlightedControl != nil {
                    // Esc/Menu from nav mode → exit nav mode, controls stay until timer.
                    highlightedControl = nil
                } else if vm.controlsVisible {
                    vm.toggleControls()
                } else {
                    vm.stop()
                    dismiss()
                }
            }
            .onChange(of: playerFocused) { _, focused in
                playerLifecycleLog.notice(
                    "[tv] playerFocused changed → \(focused) isAnyOverlayVisible=\(isAnyOverlayVisible)")
            }
    }

    // Second half of the tvOS modifier chain — split from tvosPlayerInputModifiers to
    // keep each property's generic depth under the Swift type-checker threshold.
    private var tvosPlayerOverlayModifiers: some View {
        tvosPlayerGestureModifiers
            .onChange(of: showMoreMenu) { _, visible in
                playerLifecycleLog.notice(
                    "[tv] showMoreMenu changed → \(visible) isAnyOverlayVisible=\(isAnyOverlayVisible) playerFocused=\(playerFocused)"
                )
                if visible {
                    // prefersDefaultFocus is consulted only when focus ENTERS a scope naturally.
                    // Since the overlay opens programmatically, we must explicitly route focus to
                    // the speed row so the Siri Remote Select button works immediately.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)  // one render cycle (~50 ms)
                        moreMenuFocusedRow = .speed
                        playerLifecycleLog.notice("[tv] moreMenuFocusedRow set → .speed")
                    }
                } else {
                    moreMenuFocusedRow = nil
                }
            }
            .onChange(of: showSpeedPicker) { _, visible in
                playerLifecycleLog.notice("[tv] showSpeedPicker changed → \(visible)")
                if visible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        speedPickerFocused = true
                        playerLifecycleLog.notice("[tv] speedPickerFocused set → true")
                    }
                }
            }
            .onChange(of: showQualityPicker) { _, visible in
                playerLifecycleLog.notice("[tv] showQualityPicker changed → \(visible)")
                if visible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        qualityPickerFocused = true
                        playerLifecycleLog.notice("[tv] qualityPickerFocused set → true")
                    }
                }
            }
            .onChange(of: showSleepTimerPicker) { _, visible in
                playerLifecycleLog.notice("[tv] showSleepTimerPicker changed → \(visible)")
                if visible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        sleepTimerPickerFocused = true
                        playerLifecycleLog.notice("[tv] sleepTimerPickerFocused set → true")
                    }
                }
            }
            .onChange(of: showCaptionPicker) { _, visible in
                playerLifecycleLog.notice("[tv] showCaptionPicker changed → \(visible)")
                if visible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        captionPickerFocused = true
                        playerLifecycleLog.notice("[tv] captionPickerFocused set → true")
                    }
                } else {
                    captionPickerFocused = false
                }
            }
    }

    // Third split of the tvOS modifier chain.
    private var tvosPlayerChangeModifiers: some View {
        tvosPlayerOverlayModifiers
            .onChange(of: showAudioTrackPicker) { _, visible in
                playerLifecycleLog.notice("[tv] showAudioTrackPicker changed → \(visible)")
                if visible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        audioTrackPickerFocused = true
                        playerLifecycleLog.notice("[tv] audioTrackPickerFocused set → true")
                    }
                } else {
                    audioTrackPickerFocused = false
                }
            }
            .onChange(of: vm.currentToastSegment) { _, segment in
                playerLifecycleLog.notice(
                    "[tv] currentToastSegment changed → \(segment == nil ? "nil" : segment!.category.rawValue)")
                if segment != nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        skipToastButtonFocused = true
                        playerLifecycleLog.notice("[tv] skipToastButtonFocused set → true")
                    }
                } else {
                    skipToastButtonFocused = false
                    if !isAnyOverlayVisible {
                        playerFocused = true
                    }
                }
            }
            .onChange(of: vm.controlsVisible) { _, visible in
                playerLifecycleLog.debug(
                    "[tv] controlsVisible changed → \(visible) highlighted=\(String(describing: highlightedControl)) isAnyOverlayVisible=\(isAnyOverlayVisible)"
                )
                if !visible {
                    highlightedControl = nil
                    // Only reclaim player focus when no overlay is open.
                    // focusScope(moreMenuNamespace) keeps focus inside the menu when
                    // controls hide, so no re-assertion is needed (and re-asserting
                    // would steal focus back from whichever row the user navigated to).
                    if !isAnyOverlayVisible {
                        playerFocused = true
                    }
                }
            }
            .onChange(of: isAnyOverlayVisible) { _, overlayVisible in
                playerLifecycleLog.notice(
                    "[tv] isAnyOverlayVisible changed → \(overlayVisible) — moreMenu=\(showMoreMenu) quality=\(showQualityPicker) speed=\(showSpeedPicker) sleep=\(showSleepTimerPicker)"
                )
                if overlayVisible {
                    // Pause the controls auto-hide timer so transport controls stay
                    // visible behind the overlay while it is open.
                    vm.cancelControlsHide()
                } else {
                    // Overlay dismissed — reclaim focus and clear nav state.
                    highlightedControl = nil
                    playerFocused = true
                }
            }
    }
    #endif

    var bodyWithLifecycleModifiers: some View {
        // Group branches by platform so each branch has its own type-inference scope.
        // Platform-specific toolbar and nav-bar modifiers live inside each branch to
        // avoid conditional-compilation mid-chain (not allowed outside @ViewBuilder).
        Group {
            #if os(tvOS)
            tvosPlayerChangeModifiers
                .toolbar(.hidden, for: .tabBar)
            #elseif os(iOS)
            playerContentView
                .navigationBarHidden(true)
                .statusBarHidden(true)
                .toolbar(.hidden, for: .tabBar)
            #else
            playerContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        // Always-visible title badge so XCUITest can read the current video title
        // without waiting for the controls overlay to be shown.
        // Also provides an always-accessible back button for UI automation.
        .overlay(alignment: .topLeading) {
            titleAndBackButtonOverlay
        }
        .onAppear {
            playerLifecycleLog.notice("[PlayerView] onAppear id=\(video.id)")
            isVisible = true
            #if os(tvOS)
            playerFocused = true
            #endif
            #if os(iOS)
            // fix12: Post UIAccessibility.screenChanged so XCTest's accessibility engine
            // immediately re-checks the hierarchy after this view appears. Without this,
            // XCTest polls at ~0.25s intervals and may take 1.0-1.5s to find player.titleLabel
            // even when it is already in the tree. With this notification, XCTest wakes and
            // finds the element in the next snapshot (~0.1-0.2s). Harmless in production.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            playerLifecycleLog.notice("[orientation] onAppear — calling beginGeneratingDeviceOrientationNotifications")
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let rawOrientation = UIDevice.current.orientation
            let physicallyLandscape: Bool
            if rawOrientation.isLandscape || rawOrientation.isPortrait {
                // OS has delivered a definitive device orientation.
                physicallyLandscape = rawOrientation.isLandscape
            } else {
                // rawOrientation is .unknown, .faceUp, or .faceDown — OS has not yet
                // delivered the first orientation notification. Fall back to the window
                // scene's interface orientation, which is always valid (it reflects the
                // status-bar orientation rather than the physical device sensor).
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first
                physicallyLandscape = windowScene?.interfaceOrientation.isLandscape ?? false
                playerLifecycleLog.notice(
                    "[orientation] onAppear — rawOrientation=\(rawOrientation.rawValue) is ambiguous; using windowScene interfaceOrientation=\(windowScene?.interfaceOrientation.rawValue ?? -1)"
                )
            }
            let alwaysPlayOnAppear = store.settings.landscapeAlwaysPlay
            let isLandscapeOnAppear = alwaysPlayOnAppear || physicallyLandscape
            vm.isLandscape = isLandscapeOnAppear
            playerLifecycleLog.notice(
                "[orientation] onAppear — rawOrientation=\(rawOrientation.rawValue) physicallyLandscape=\(physicallyLandscape) landscapeAlwaysPlay=\(alwaysPlayOnAppear) → isLandscape=\(isLandscapeOnAppear)"
            )
            if alwaysPlayOnAppear {
                playerLifecycleLog.notice(
                    "[orientation] onAppear — landscapeAlwaysPlay=true, setting playerIsActive=true")
                OrientationManager.shared.playerIsActive = true
            } else {
                playerLifecycleLog.notice(
                    "[orientation] onAppear — landscapeAlwaysPlay=false, playerIsActive remains false")
            }
            #endif
            #if os(iOS)
            // On iOS, PlayerStateStore.play(video:) already called vm.load() before
            // presenting. Only sync current user preferences; the video is already loading.
            vm.setPlaybackSpeed(store.settings.playbackSpeed)
            vm.updateSettings(store.settings)
            vm.updateAuthToken(authService.accessToken)
            vm.updateSAPISID(authService.sapisid)
            // Expanding from the mini-player gives a fresh @State with no controller while
            // isPlaying stays true, so onChange(of: vm.isPlaying) alone would never create one.
            ensurePiPController()
            if ProcessInfo.processInfo.arguments.contains("--uitesting-open-more-menu") {
                playerLifecycleLog.notice(
                    "[PlayerView] --uitesting-open-more-menu launch arg detected — scheduling showMoreMenu=true")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    playerLifecycleLog.notice("[PlayerView] --uitesting-open-more-menu: setting showMoreMenu=true")
                    showMoreMenu = true
                }
            }
            // UI testing only: force-show controls and cancel the auto-hide timer so
            // the controls overlay stays on screen for the duration of the test.
            // Works correctly because vm.load() was already called from PlayerStateStore.play()
            // before this view appears, so controlsVisible was reset to false by load()
            // and we can unconditionally restore it here.
            if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
                playerLifecycleLog.notice(
                    "[PlayerView] --uitesting-show-controls launch arg detected — showing controls")
                vm.showControls()
                vm.cancelControlsHide()
            }
            #else
            if vm.currentVideoId == video.id {
                // Spurious appear (e.g. a sheet temporarily covered us) — only resume
                // if playback was active before the view disappeared, so an intentional
                // user pause is not overridden (e.g. pause → background → foreground).
                if vm.wasPlayingBeforeSuspend {
                    vm.resume()
                }
            } else {
                vm.load(video: video)
            }
            vm.setPlaybackSpeed(store.settings.playbackSpeed)
            vm.updateSettings(store.settings)
            vm.updateAuthToken(authService.accessToken)
            // UI testing only: force-show controls so the test can find player.nextBtn.
            if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
                playerLifecycleLog.notice("[PlayerView] --uitesting-show-controls (non-iOS) — showing controls")
                vm.showControls()
                vm.cancelControlsHide()
            }
            // UI testing only: force-show controls and/or the more menu so tests can
            // verify focus routing without relying on gesture delivery, which is
            // unreliable on the tvOS simulator.
            // Called AFTER load() so it runs after controlsVisible is reset to false.
            // cancelControlsHide() keeps the overlay permanently on screen for tests
            // that need to interact with controls elements.
            if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
                playerLifecycleLog.notice("[tv] --uitesting-show-controls launch arg detected — calling showControls()")
                vm.showControls()
                vm.cancelControlsHide()
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-open-more-menu") {
                playerLifecycleLog.notice(
                    "[tv] --uitesting-open-more-menu launch arg detected — scheduling showMoreMenu=true after focus settles"
                )
                Task { @MainActor in
                    // Brief delay lets the player body establish focus (via .prefersDefaultFocus)
                    // before the overlay opens, so moreMenuNamespace can attract focus correctly.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    playerLifecycleLog.notice("[tv] --uitesting-open-more-menu: setting showMoreMenu=true")
                    showMoreMenu = true
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-open-sleep-timer-picker") {
                playerLifecycleLog.notice(
                    "[tv] --uitesting-open-sleep-timer-picker launch arg detected — scheduling showSleepTimerPicker=true"
                )
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    playerLifecycleLog.notice(
                        "[tv] --uitesting-open-sleep-timer-picker: setting showSleepTimerPicker=true")
                    showSleepTimerPicker = true
                }
            }
            #endif
        }
        .onDisappear {
            playerLifecycleLog.notice("[PlayerView] onDisappear id=\(video.id) isInBackground=\(isInBackground)")
            isVisible = false
            guard !isInBackground else { return }
            #if os(iOS)
            let rawOrientationOnDisappear = UIDevice.current.orientation
            playerLifecycleLog.notice(
                "[orientation] onDisappear — rawOrientation=\(rawOrientationOnDisappear.rawValue) isLandscape was \(vm.isLandscape), playerIsActive was \(OrientationManager.shared.playerIsActive)"
            )
            OrientationManager.shared.playerIsActive = false
            vm.isLandscape = false
            playerLifecycleLog.notice(
                "[orientation] onDisappear — playerIsActive=false isLandscape=false, calling endGeneratingDeviceOrientationNotifications"
            )
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            // Skip suspend when minimizing to mini-player — playback should continue.
            guard playerState.presentation != .miniPlayer else { return }
            // Player view is being fully dismissed — release PiP controller so the
            // next play session creates a fresh one bound to the current playerLayer.
            pipController = nil
            pipDelegate = nil
            vm.suspend()
            #else
            vm.suspend()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                isInBackground = true
                if isVisible { vm.handleBackground() }
            case .active:
                isInBackground = false
                if isVisible { vm.handleForeground() }
            default:
                break
            }
        }
        #if os(iOS)
        .onChange(of: vm.isPlaying) { _, _ in ensurePiPController() }
        // Update isLandscape when the device physically rotates.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            playerLifecycleLog.notice(
                "[orientation] orientationDidChange — rawValue=\(orientation.rawValue) isValidInterfaceOrientation=\(orientation.isValidInterfaceOrientation) isLandscape=\(orientation.isLandscape) isPortrait=\(orientation.isPortrait)"
            )
            guard orientation.isValidInterfaceOrientation else {
                playerLifecycleLog.notice(
                    "[orientation] orientationDidChange — skipped (not a valid interface orientation, e.g. face-up/face-down/unknown)"
                )
                return
            }
            let alwaysLandscape = store.settings.landscapeAlwaysPlay
            let physicalLandscape = orientation.isLandscape
            let newIsLandscape = isLandscapeLocked || alwaysLandscape || physicalLandscape
            let prevIsLandscape = vm.isLandscape
            let prevPlayerIsActive = OrientationManager.shared.playerIsActive
            vm.isLandscape = newIsLandscape
            OrientationManager.shared.playerIsActive = newIsLandscape
            playerLifecycleLog.notice(
                "[orientation] orientationDidChange — landscapeLocked=\(isLandscapeLocked) landscapeAlwaysPlay=\(alwaysLandscape) physicalLandscape=\(physicalLandscape) isLandscape: \(prevIsLandscape) → \(newIsLandscape) playerIsActive: \(prevPlayerIsActive) → \(newIsLandscape)"
            )
        }
        // Keep isLandscape in sync when the user toggles "Landscape Always Play" while
        // the player is on screen.
        .onChange(of: store.settings.landscapeAlwaysPlay) { oldValue, alwaysLandscape in
            let rawOrientation = UIDevice.current.orientation
            let physicallyLandscape = rawOrientation.isLandscape
            let newIsLandscape = isLandscapeLocked || alwaysLandscape || physicallyLandscape
            let prevIsLandscape = vm.isLandscape
            let prevPlayerIsActive = OrientationManager.shared.playerIsActive
            vm.isLandscape = newIsLandscape
            OrientationManager.shared.playerIsActive = isLandscapeLocked || alwaysLandscape
            playerLifecycleLog.notice(
                "[orientation] landscapeAlwaysPlay: \(oldValue) → \(alwaysLandscape) landscapeLocked=\(isLandscapeLocked) rawOrientation=\(rawOrientation.rawValue) physicallyLandscape=\(physicallyLandscape) isLandscape: \(prevIsLandscape) → \(newIsLandscape) playerIsActive: \(prevPlayerIsActive) → \(isLandscapeLocked || alwaysLandscape)"
            )
        }
        // Apply orientation immediately when the lock button is tapped.
        .onChange(of: isLandscapeLocked) { oldValue, isLocked in
            let rawOrientation = UIDevice.current.orientation
            let physicallyLandscape = rawOrientation.isLandscape
            let alwaysLandscape = store.settings.landscapeAlwaysPlay
            let newIsLandscape = isLocked || alwaysLandscape || physicallyLandscape
            let prevIsLandscape = vm.isLandscape
            let prevPlayerIsActive = OrientationManager.shared.playerIsActive
            vm.isLandscape = newIsLandscape
            OrientationManager.shared.playerIsActive = isLocked || alwaysLandscape
            playerLifecycleLog.notice(
                "[orientation] landscapeLocked: \(oldValue) → \(isLocked) alwaysLandscape=\(alwaysLandscape) physicallyLandscape=\(physicallyLandscape) isLandscape: \(prevIsLandscape) → \(newIsLandscape) playerIsActive: \(prevPlayerIsActive) → \(isLocked || alwaysLandscape)"
            )
        }
        #endif
        .navigationDestination(item: $channelDestination) { dest in
            ChannelView(channelId: dest.channelId)
        }
        #if !os(tvOS) && ENABLE_DOWNLOADS
        .onChange(of: downloadService.state) { _, newState in
            switch newState {
            case .done:
                let title = vm.playerInfo?.video.title ?? video.title
                downloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Saved to Gallery", bundle: .module),
                    message: String(localized: "\"\(title)\" has been saved to your Photos library.", bundle: .module)
                )
                downloadService.reset()
            case .failed(let reason):
                downloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Download Failed", bundle: .module),
                    message: reason
                )
                downloadService.reset()
            default:
                break
            }
        }
        .feedbackAlert(item: $downloadAlertItem)
        #endif
        // Intercept smarttube://seek/<seconds> links emitted by timestamp spans in
        // descriptions and comments, and forward them to the player seek function.
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "smarttube", url.host == "seek",
                    let seconds = TimeInterval(url.lastPathComponent)
                {
                    vm.seek(to: seconds)
                    return .handled
                }
                return .systemAction
            })
    }

    #if os(iOS)
    /// Creates the PiP controller once the player is actually playing (AVPlayer needs a
    /// ready item, otherwise isPictureInPicturePossible never becomes true), and releases
    /// it when PiP is turned off in settings. The controller is kept after PiP ends:
    /// playerLayer is owned by playerState and outlives PiP (TD-5). Called from onAppear
    /// and onChange(of: vm.isPlaying); also released in onDisappear on full dismissal.
    func ensurePiPController() {
        guard store.settings.pipEnabled else {
            pipController = nil
            pipDelegate = nil
            return
        }
        let pipUITestingOverride = ProcessInfo.processInfo.arguments.contains("--uitesting-enable-pip")
        guard vm.isPlaying, pipController == nil,
            playerLayer.player != nil,
            pipUITestingOverride || AVPictureInPictureController.isPictureInPictureSupported()
        else { return }
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.canStartPictureInPictureAutomaticallyFromInline = true
        let delegate = PiPDelegate(
            onActiveChange: { active in isPiPActive = active },
            onDidStart: { vm.updateNowPlayingInfo() }
        )
        pip?.delegate = delegate
        pipDelegate = delegate
        pipController = pip
    }
    #endif

    // MARK: - Controls overlay

    /// Constructs the platform-appropriate `PlayerControlsOverlay` for this view.
    @ViewBuilder
    func makeControlsOverlay(size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        #if os(iOS)
        PlayerControlsOverlay(
            size: size,
            safeAreaInsets: safeAreaInsets,
            video: video,
            controlScale: controlScale,
            showMoreMenu: $showMoreMenu,
            channelDestination: $channelDestination,
            pipController: $pipController,
            isPiPActive: $isPiPActive,
            isLandscapeLocked: $isLandscapeLocked,
            showQualityPicker: $showQualityPicker,
            showSpeedPicker: $showSpeedPicker,
            showAudioTrackPicker: $showAudioTrackPicker,
            showSleepTimerPicker: $showSleepTimerPicker
        )
        #elseif os(tvOS)
        PlayerControlsOverlay(
            size: size,
            safeAreaInsets: safeAreaInsets,
            video: video,
            controlScale: controlScale,
            showMoreMenu: $showMoreMenu,
            channelDestination: $channelDestination,
            vm: vm,
            highlightedControl: $highlightedControl
        )
        #else
        PlayerControlsOverlay(
            size: size,
            safeAreaInsets: safeAreaInsets,
            video: video,
            controlScale: controlScale,
            showMoreMenu: $showMoreMenu,
            channelDestination: $channelDestination,
            vm: vm,
            showQualityPicker: $showQualityPicker,
            showSpeedPicker: $showSpeedPicker,
            showAudioTrackPicker: $showAudioTrackPicker,
            showSleepTimerPicker: $showSleepTimerPicker
        )
        #endif
    }

    // MARK: - Audio-only thumbnail overlay

    /// Shown in place of the video layer when `vm.isAudioOnlyMode == true`.
    /// The AVPlayerLayer is kept in the hierarchy (for PiP continuity) but covered by this view.
    @ViewBuilder
    var audioOnlyThumbnailOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let thumb = vm.playerInfo?.video.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.6))
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Audio only — thumbnail")
        .accessibilityIdentifier("player.audioOnlyOverlay")
    }
}
