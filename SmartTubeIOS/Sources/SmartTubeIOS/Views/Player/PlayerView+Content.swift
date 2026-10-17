import AVFoundation
import AVKit
import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

extension PlayerView {
    // MARK: - Title and back-button overlay
    //
    // Extracted from bodyWithLifecycleModifiers to keep the Swift type-checker from
    // timing out on the cumulative modifier chain in that var (compiler error:
    // "unable to type-check this expression in reasonable time").
    @ViewBuilder
    var titleAndBackButtonOverlay: some View {
        HStack(spacing: 0) {
            Button {
                #if os(iOS)
                playerLifecycleLog.notice(
                    "[PlayerView] backButton tapped — miniPlayerEnabled=\(store.settings.miniPlayerEnabled) presentation=\(String(describing: playerState.presentation))"
                )
                if store.settings.miniPlayerEnabled { playerState.minimize() } else { playerState.stop() }
                playerLifecycleLog.notice(
                    "[PlayerView] backButton — done, presentation=\(String(describing: playerState.presentation))")
                #else
                vm.stop()
                withAnimation(.none) { dismiss() }
                #if os(macOS)
                browseVM.deepLinkedVideo = nil
                #endif
                #endif
            } label: {
                Color.clear.frame(width: 60, height: 60)
            }
            .accessibilityIdentifier(AccessibilityID.playerBackButton)
            #if os(tvOS)
            .buttonStyle(.plain)
            .focusable(false)
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

    // MARK: - Player content base view
    //
    // Contains the GeometryReader / ZStack with AVLayer, controls, and iOS swipe gesture.
    // Extracted from bodyWithLifecycleModifiers so the Swift type-checker handles each
    // property in a separate inference scope (compiler error: "unable to type-check
    // this expression in reasonable time").
    var playerContentView: some View {
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
                // Horizontal swipe layer: left → next video, right → previous video.
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
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
                            scaleToast = newMode == .fill ? "Fill" : "Fit"
                            seekToastMessage = newMode == .fill ? "Fill" : "Fit"  // diagnostic: also set seekToast
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
                    },
                    onLongPressStart: { vm.beginHoldSpeed() },
                    onLongPressEnd: { vm.endHoldSpeed() },
                    onSwipeDown: {
                        if store.settings.miniPlayerEnabled {
                            playerState.minimize()
                        } else {
                            playerState.stop()
                        }
                    },
                    // Disabled during scrubbing so the Slider can claim touches uncontested.
                    // Also disabled when controls are visible so SwiftUI buttons (Menu, etc.)
                    // receive touches directly without UIKit gesture interference.
                    isEnabled: !vm.isScrubbing && !vm.controlsVisible
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
                #endif

                #if os(macOS)
                // Transparent click layer for macOS — toggles controls overlay on click.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { if !vm.hasVisibleEndCards { vm.toggleControls() } }
                    .ignoresSafeArea()
                #endif

                // Loading spinner
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
                    .allowsHitTesting(false)
                }

                // Yandex voice-over: a compact top-corner badge while the video is held for the translation.
                if case .waiting(let remaining) = vm.voiceOver.state, !vm.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("Yandex translating")
                        if let remaining, remaining > 0 {
                            Text("~\(max(1, remaining / 60)) min").foregroundStyle(.white.opacity(0.7))
                        }
                        Button {
                            vm.setVoiceOverForCurrentVideo(false)
                        } label: {
                            Image(systemName: AppSymbol.xmarkCircle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Watch Without Translation")
                        .accessibilityIdentifier(AccessibilityID.playerVoiceOverCancelButton)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
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
                        .animation(.easeOut(duration: 0.15), value: vm.isHoldingToSpeed)
                }
                #endif

                // Custom overlay controls
                if vm.controlsVisible {
                    makeControlsOverlay(size: geo.size, safeAreaInsets: geo.safeAreaInsets)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: vm.controlsVisible)
                        #if os(iOS)
                    // Allow horizontal swipe navigation even when the controls overlay is
                    // on screen.  .simultaneousGesture fires alongside button taps so the
                    // controls remain fully interactive; only clear horizontal drags
                    // (abs(dx) > abs(dy), distance > 50 pt) trigger navigation.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 50, coordinateSpace: .global)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                guard !isTransitioning, !vm.isScrubbing else { return }
                                // Swipe-down → minimize to mini-player (or stop if disabled)
                                if dy > 50, abs(dy) > abs(dx) {
                                    if store.settings.miniPlayerEnabled {
                                        playerState.minimize()
                                    } else {
                                        playerState.stop()
                                    }
                                    return
                                }
                                guard abs(dx) > abs(dy) else { return }
                                if dx < 0, vm.hasNext {
                                    performHorizontalTransition(direction: -1, screenWidth: geo.size.width) {
                                        vm.playNext()
                                    }
                                } else if dx > 0, vm.hasPrevious {
                                    performHorizontalTransition(direction: 1, screenWidth: geo.size.width) {
                                        vm.playPrevious()
                                    }
                                }
                            }
                    )
                        #endif
                }

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
                            // When controls are visible the scrub bar + bottom controls
                            // occupy ~130pt. Push captions above that area. When controls
                            // are hidden, a small margin from the safe-area bottom is enough.
                            .padding(.bottom, vm.controlsVisible ? 130 : 24)
                            .animation(.easeInOut(duration: 0.2), value: vm.controlsVisible)
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
                    .animation(.easeInOut(duration: 0.25), value: vm.controlsVisible)
                }
                #endif

                // Stats for Nerds overlay (toggled by two-finger tap)
                if vm.statsForNerdsVisible {
                    StatsForNerdsOverlay(snapshot: vm.statsSnapshot)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: vm.statsForNerdsVisible)
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
