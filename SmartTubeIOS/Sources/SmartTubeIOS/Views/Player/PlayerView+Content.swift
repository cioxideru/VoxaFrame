import AVFoundation
import AVKit
import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

extension PlayerView {
    /// Caption bottom margin while the controls show. iPhone, iPad and Mac: the bottom bar's measured height, which
    /// follows the layout and text size. TV keeps its margin, as its controls are unchanged.
    var captionLiftAboveControls: CGFloat {
        #if os(tvOS)
        130
        #else
        controlsBottomBarHeight + VFSpace.s8
        #endif
    }

    // MARK: - Title and back-button overlay
    //
    // Extracted from bodyWithLifecycleModifiers to keep the Swift type-checker from
    // timing out on the cumulative modifier chain in that var (compiler error:
    // "unable to type-check this expression in reasonable time").
    @ViewBuilder
    var titleAndBackButtonOverlay: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            Button(action: macBackAction) {
                Color.clear.frame(width: VFTarget.touch, height: VFTarget.touch)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityIdentifier(AccessibilityID.playerBackButton)
            .accessibilityLabel(
                macWindow.isFullScreen ? Text("Exit Full Screen", bundle: .module) : Text("Back", bundle: .module)
            )
            .accessibilityHidden(false)
            // Keep AXPress available when controls hide without taking clicks from the video surface.
            .allowsHitTesting(false)
            #else
            Button {
                #if os(iOS)
                playerLifecycleLog.notice(
                    "[PlayerView] backButton tapped — miniPlayerEnabled=\(store.settings.miniPlayerEnabled) presentation=\(String(describing: playerState.presentation))"
                )
                if store.settings.miniPlayerEnabled {
                    playerState.minimize(reason: "back-overlay")
                } else {
                    playerState.stop()
                }
                playerLifecycleLog.notice(
                    "[PlayerView] backButton — done, presentation=\(String(describing: playerState.presentation))")
                #else
                vm.stop()
                withAnimation(.none) { dismiss() }
                #endif
            } label: {
                Color.clear.frame(width: 60, height: 60)
            }
            .accessibilityIdentifier(AccessibilityID.playerBackButton)
            #if os(tvOS)
            .buttonStyle(.plain)
            .focusable(false)
            #endif
            #endif
            Text(vm.playerInfo?.video.title ?? video.title)
                .font(.caption)
                .opacity(0)  // visually invisible (including emoji), accessible
                .accessibilityIdentifier(AccessibilityID.playerTitleLabel)
                .accessibilityLabel(vm.playerInfo?.video.title ?? video.title)
                // macOS AX prunes opacity-0 elements by default — force the element
                // into the accessibility tree so XCUITest can always read it.
                .accessibilityHidden(false)
                .allowsHitTesting(false)
            // Probe stream result — only present during single-method probe runs.
            // Exposes the stream type + max resolution so StreamMethodProbeUITests
            // can read it without needing to parse device logs.
            if let result = vm.probeStreamResult {
                Text(result)
                    .font(.caption)
                    .opacity(0)
                    .accessibilityIdentifier(AccessibilityID.playerProbeStreamResult)
                    .accessibilityLabel(result)
                    .accessibilityHidden(false)
                    .allowsHitTesting(false)
            }
        }
        #if !os(tvOS)
        .padding(.top, 60)
        #endif
    }

    #if os(macOS)
    func macBackAction() {
        if macWindow.isFullScreen {
            macWindow.exitFullScreen()
        } else {
            vm.stop()
            withAnimation(.none) { dismiss() }
            browseVM.deepLinkedVideo = nil
        }
    }
    #endif

    // MARK: - Player content base view
    //
    // Contains the GeometryReader / ZStack with AVLayer, controls, and iOS swipe gesture.
    // Extracted from bodyWithLifecycleModifiers so the Swift type-checker handles each
    // property in a separate inference scope (compiler error: "unable to type-check
    // this expression in reasonable time"). `playerContentView` adds the option panels.
    var playerContentBase: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                #if os(iOS)
                // PersistentPlayerLayerView: wraps PersistentPlayerHostView so the AVPlayerLayer
                // survives PlayerView dismiss/re-present cycles (mini-player feature).
                PersistentPlayerLayerView(
                    presentation: .fullScreen,
                    videoGravity: store.settings.videoGravityMode.avGravity
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
                // Audio-only mode: overlay the thumbnail over the (hidden) player layer.
                // The AVPlayerLayer stays in the hierarchy so PiP attachment is undisturbed.
                if vm.isAudioOnlyMode {
                    audioOnlyThumbnailOverlay
                }
                #elseif os(tvOS)
                // PlayerAVLayerView: bare AVPlayerLayer without AVPlayerViewController.
                // AVPlayerViewController (VideoPlayer) dominates the UIKit accessibility
                // tree, making all overlaid SwiftUI elements invisible to XCUITest.
                PlayerAVLayerView(player: vm.player, videoGravity: store.settings.videoGravityMode.avGravity)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                if vm.isAudioOnlyMode {
                    audioOnlyThumbnailOverlay
                }
                #elseif os(macOS)
                PlayerNSLayerView(player: vm.player, videoGravity: store.settings.videoGravityMode.avGravity)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                if vm.isAudioOnlyMode {
                    audioOnlyThumbnailOverlay
                }
                #else
                Color.black.ignoresSafeArea()
                #endif

                #if os(iOS)
                // One gesture surface for navigation, taps and vertical level adjustment.
                // Uses UIKit-level UIPanGestureRecognizer so it fires above AVPlayerLayer.
                PlayerSwipeGestureOverlay(
                    onSwipeLeft: {
                        playerLifecycleLog.debug(
                            "[swipe-overlay] onSwipeLeft — isTransitioning=\(isTransitioning) isScrubbing=\(vm.isScrubbing) controlsVisible=\(vm.controlsVisible) hasNext=\(vm.hasNext)"
                        )
                        guard !isTransitioning else { return }
                        if vm.hasNext {
                            performHorizontalTransition(direction: -1, screenWidth: geo.size.width) { vm.playNext() }
                        } else {
                            snapBack()
                        }
                    },
                    onSwipeRight: {
                        playerLifecycleLog.debug(
                            "[swipe-overlay] onSwipeRight — isTransitioning=\(isTransitioning) isScrubbing=\(vm.isScrubbing) controlsVisible=\(vm.controlsVisible) hasPrevious=\(vm.hasPrevious)"
                        )
                        guard !isTransitioning else { return }
                        if vm.hasPrevious {
                            performHorizontalTransition(direction: 1, screenWidth: geo.size.width) { vm.playPrevious() }
                        } else {
                            snapBack()
                        }
                    },
                    onTap: {
                        // Suppress toggle-controls when end cards are active — taps belong to the cards.
                        if !vm.hasVisibleEndCards { vm.toggleControls() }
                    },
                    onDoubleTap: { normalizedX in
                        if normalizedX < 1.0 / 3.0 {
                            vm.seekRelative(seconds: -Double(store.settings.seekBackSeconds))
                            seekToastMessage = "← \(store.settings.seekBackSeconds)s"
                        } else if normalizedX > 2.0 / 3.0 {
                            vm.seekRelative(seconds: Double(store.settings.seekForwardSeconds))
                            seekToastMessage = "\(store.settings.seekForwardSeconds)s →"
                        } else {
                            store.settings.videoGravityMode.toggle()
                            let newMode = store.settings.videoGravityMode
                            scaleToast =
                                newMode == .fill
                                ? String(localized: "Fill", bundle: .module) : String(localized: "Fit", bundle: .module)
                        }
                    },
                    onTwoFingerTap: { vm.toggleStatsForNerds() },
                    onPanChanged: { dx in
                        guard !isTransitioning else { return }
                        if (dx < 0 && vm.hasNext) || (dx > 0 && vm.hasPrevious) {
                            slideOffset = dx
                        } else {
                            slideOffset = dx * 0.15
                        }
                    },
                    onSwipeCancelled: {
                        snapBack()
                    },
                    onLongPressStart: { vm.beginHoldSpeed() },
                    onLongPressEnd: { vm.endHoldSpeed() },
                    onSwipeDown: {
                        if store.settings.miniPlayerEnabled {
                            playerState.minimize(reason: "swipe-down")
                        } else {
                            playerState.stop()
                        }
                    },
                    onLevelChanged: { showLevelFeedback($0, value: $1) },
                    onLevelEnded: { finishLevelAdjustment() },
                    isActive: playerState.presentation == .fullScreen,
                    isEnabled: !vm.isScrubbing && !isTransitioning && !vm.hasVisibleEndCards
                        && !showMoreMenu && !showQualityPicker && !showSpeedPicker && !showCaptionPicker
                        && !showAudioTrackPicker && !showSleepTimerPicker && !showDescriptionSheet && !showCommentsSheet
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
                #endif

                #if os(macOS)
                MacPlayerClickSurface(vm: vm, focused: $macPlayerFocused)
                    .ignoresSafeArea()
                #endif

                // Loading: a spinner on a glass disc, with the retry status under it (P-Player-States).
                if vm.isLoading {
                    PlayerLoadingIndicator(message: vm.retryStatusMessage)
                        .allowsHitTesting(false)
                }

                // Yandex voice-over: preparing (the video waits) or failed, each with its way out, under the top bar.
                if !vm.isLoading {
                    PlayerTranslationStatus(vm: vm)
                        .padding(.horizontal, VFSpace.s16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, VFSpace.s20) + VFTarget.touch + VFSpace.s12)
                        .transition(.opacity)
                }

                #if DEBUG
                if OfflineUITestFixture.baseURL != nil {
                    Text(OfflineUITestFixture.status(vm))
                        .font(.caption2)
                        .accessibilityIdentifier(AccessibilityID.offlinePlaybackStatus)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                #endif

                // Hold-to-speed badge — shown while user long-presses to boost to 2×
                #if os(iOS) || os(tvOS)
                if vm.isHoldingToSpeed {
                    HoldSpeedBadge()
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .vfAnimation(VFMotion.fast, value: vm.isHoldingToSpeed)
                }
                #endif

                // Custom overlay controls
                if vm.controlsVisible {
                    makeControlsOverlay(size: geo.size, safeAreaInsets: geo.safeAreaInsets)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .vfAnimation(value: vm.controlsVisible)
                }

                #if os(iOS) && !targetEnvironment(macCatalyst)
                levelGestureOverlay
                #endif

                // Error banner
                if let err = vm.error {
                    errorBanner(err)
                }

                // SponsorBlock skip toast
                sponsorSkipToast

                // Caption cue overlay — shown when a track is selected and a cue is active
                if let cue = vm.currentCaptionCue {
                    VStack(spacing: 0) {
                        Spacer()
                        CaptionCueView(text: cue.text)
                            // Above the bottom controls while they show; when they are hidden, a small
                            // margin from the safe-area bottom is enough.
                            .padding(.bottom, vm.controlsVisible ? captionLiftAboveControls : 24)
                            .vfAnimation(value: vm.controlsVisible)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                // End cards — shown in the final seconds of a video.
                // Displayed regardless of controls visibility, matching official YouTube behaviour.
                #if !os(tvOS)
                if !vm.endCards.isEmpty {
                    EndCardOverlay(
                        cards: vm.endCards,
                        currentTime: vm.currentTime,
                        onSelect: { card in
                            guard let videoId = card.videoId else { return }
                            let video = Video(
                                id: videoId,
                                title: card.title,
                                channelTitle: "",
                                thumbnailURL: card.thumbnailURL
                            )
                            vm.load(video: video)
                        }
                    )
                    .transition(.opacity)
                    .vfAnimation(value: vm.controlsVisible)
                }
                #endif

                // Stats for Nerds overlay (toggled by two-finger tap)
                if vm.statsForNerdsVisible {
                    StatsForNerdsOverlay(snapshot: vm.statsSnapshot)
                        .transition(.opacity)
                        .vfAnimation(value: vm.statsForNerdsVisible)
                }

                // Picker / sheet overlays — see PlayerView+Overlays.swift
                overlayStack
            }
            .offset(x: slideOffset)
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .toast(message: $scaleToast)
        .toast(message: $seekToastMessage)
        .toast(message: $qualityToastMessage)
        .toast(message: Binding(get: { vm.toastMessage }, set: { vm.toastMessage = $0 }))
        #endif
    }

}
