import AVFoundation
import AVKit
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private let controlsLog = ViewModelLogger(category: "Player")

// MARK: - PlayerControlsOverlay
//
// Dedicated view for the interactive transport controls overlaid on the player.
// Extracted from PlayerView.body to reduce the compiled function size and
// the Swift generic type tree depth in __swift5_typeref.

struct PlayerControlsOverlay: View {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let video: Video
    let controlScale: CGFloat
    @Binding var showMoreMenu: Bool
    @Binding var channelDestination: ChannelDestination?

    #if os(iOS)
    let pipController: AVPictureInPictureController?
    let isPiPActive: Bool
    @Binding var isLandscapeLocked: Bool
    @Environment(PlayerStateStore.self) private var playerState
    var vm: PlaybackViewModel { playerState.vm }
    #else
    let vm: PlaybackViewModel
    #endif
    #if !os(tvOS)
    @Binding var showQualityPicker: Bool
    @Binding var showSpeedPicker: Bool
    @Binding var showAudioTrackPicker: Bool
    @Binding var showSleepTimerPicker: Bool
    #endif
    #if os(tvOS)
    @Binding var highlightedControl: PlayerView.TVPlayerControl?
    #endif
    @Environment(SettingsStore.self) var store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack {
            // Top bar: back + title
            HStack {
                #if os(tvOS)
                tvOverlayControl(
                    highlighted: highlightedControl == .back,
                    scale: 1.5,
                    shadowRadius: 12,
                    identifier: "player.backButton",
                    width: 64,
                    height: 64
                ) {
                    Image(systemName: AppSymbol.chevronLeft)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                #else
                Button {
                    #if os(iOS)
                    if store.settings.miniPlayerEnabled { playerState.minimize() } else { playerState.stop() }
                    #else
                    vm.stop()
                    withAnimation(.none) { dismiss() }
                    #endif
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier(AccessibilityID.playerBackButton)
                #endif
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.playerInfo?.video.title ?? video.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.playerTitleLabel)
                    let channelId = vm.playerInfo?.video.channelId ?? video.channelId
                    let channelTitle = vm.playerInfo?.video.channelTitle ?? video.channelTitle
                    #if os(tvOS)
                    tvOverlayControl(
                        highlighted: highlightedControl == .channel,
                        scale: 1.5,
                        shadowRadius: 12,
                        identifier: "player.channelName",
                        enabled: channelId?.isEmpty == false
                    ) {
                        Text(channelTitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    #else
                    Button {
                        guard let cid = channelId, !cid.isEmpty else { return }
                        #if os(iOS)
                        // PlayerView is presented via fullScreenCover — there is no
                        // NavigationStack, so setting channelDestination is a no-op.
                        // Post the shared notification instead (same path as VideoCardView),
                        // then dismiss the player so the parent can push ChannelView.
                        NotificationCenter.default.post(
                            name: .openChannel,
                            object: nil,
                            userInfo: ["channelId": cid]
                        )
                        dismiss()
                        #else
                        channelDestination = ChannelDestination(channelId: cid)
                        #endif
                    } label: {
                        Text(channelTitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.channelName")
                    .disabled(channelId == nil || channelId?.isEmpty == true)
                    #endif
                }
                Spacer()
                videoScaleButton
                #if os(iOS)
                // Picture-in-Picture button — shown when PiP is enabled in settings and supported on this device
                if store.settings.pipEnabled, let pip = pipController {
                    Button {
                        if isPiPActive {
                            pip.stopPictureInPicture()
                        } else {
                            pip.startPictureInPicture()
                        }
                    } label: {
                        Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.playerPiPButton)
                }
                // AirPlay route picker
                AirPlayRoutePickerView()
                    .frame(width: 40, height: 40)
                    .accessibilityIdentifier("player.airPlayButton")
                #endif
                // Share / Download menu
                #if os(tvOS)
                tvOverlayControl(
                    highlighted: highlightedControl == .more,
                    scale: 1.5,
                    shadowRadius: 12,
                    identifier: AccessibilityID.playerMoreButton,
                    width: 64,
                    height: 64
                ) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18 * controlScale))
                        .foregroundStyle(.white)
                }
                #else
                Button {
                    controlsLog.notice(
                        "[menu] ... button tapped — controlsVisible=\(vm.controlsVisible) showMoreMenu=\(showMoreMenu)")
                    showMoreMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18 * controlScale))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier(AccessibilityID.playerMoreButton)
                .buttonStyle(.plain)
                #endif
            }
            .padding(.horizontal, 20)
            #if os(tvOS)
            .padding(.top, 0)
            #else
            .padding(.top, max(safeAreaInsets.top, 20))
            #endif

            Spacer()

            // Centre: rewind / play-pause / forward
            HStack(spacing: 40) {
                #if os(tvOS)
                seekButton(
                    symbol: "gobackward.\(store.settings.seekBackSeconds)",
                    seconds: -Double(store.settings.seekBackSeconds),
                    tvHighlighted: highlightedControl == .seekBack)
                #else
                seekButton(
                    symbol: "gobackward.\(store.settings.seekBackSeconds)",
                    seconds: -Double(store.settings.seekBackSeconds))
                #endif
                playPauseButton
                #if os(tvOS)
                seekButton(
                    symbol: "goforward.\(store.settings.seekForwardSeconds)",
                    seconds: Double(store.settings.seekForwardSeconds),
                    tvHighlighted: highlightedControl == .seekForward)
                #else
                seekButton(
                    symbol: "goforward.\(store.settings.seekForwardSeconds)",
                    seconds: Double(store.settings.seekForwardSeconds))
                #endif
            }
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.3 : 1)

            Spacer()

            // Bottom: progress bar + prev/next
            VStack(spacing: 8) {
                // Current chapter title — shown whenever chapters are available
                if let chapter = vm.currentChapter {
                    Text(chapter.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: chapter.title)
                }
                progressBar
                #if !os(tvOS)
                quickAccessButtonRow
                #endif
                HStack {
                    // Previous video button
                    #if os(tvOS)
                    tvOverlayControl(
                        highlighted: highlightedControl == .prevVideo,
                        scale: 1.55,
                        shadowRadius: 14,
                        identifier: "player.prevBtn",
                        enabled: vm.hasPrevious && !vm.isLoading,
                        width: 64,
                        height: 64
                    ) {
                        Image(systemName: AppSymbol.previousTrack)
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(vm.hasPrevious && !vm.isLoading ? .white : .white.opacity(0.3))
                    }
                    #else
                    Button {
                        vm.playPrevious()
                    } label: {
                        Image(systemName: AppSymbol.previousTrack)
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(vm.hasPrevious && !vm.isLoading ? .white : .white.opacity(0.3))
                            #if os(iOS)
                        .padding(8)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                            #endif
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.hasPrevious || vm.isLoading)
                    .accessibilityIdentifier("player.prevBtn")
                    #endif

                    // Previous chapter button — only present when the video has chapters
                    if !vm.chapters.isEmpty {
                        #if os(tvOS)
                        tvOverlayControl(
                            highlighted: highlightedControl == .prevChapter,
                            scale: 1.55,
                            shadowRadius: 14,
                            identifier: "player.prevChapterBtn",
                            enabled: vm.hasPreviousChapter && !vm.isLoading,
                            width: 64,
                            height: 64
                        ) {
                            Image(systemName: AppSymbol.previousChapter)
                                .font(.system(size: 18 * controlScale))
                                .foregroundStyle(vm.hasPreviousChapter && !vm.isLoading ? .white : .white.opacity(0.3))
                        }
                        #else
                        Button {
                            vm.skipToPreviousChapter()
                        } label: {
                            Image(systemName: AppSymbol.previousChapter)
                                .font(.system(size: 18 * controlScale))
                                .foregroundStyle(vm.hasPreviousChapter && !vm.isLoading ? .white : .white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.hasPreviousChapter || vm.isLoading)
                        .accessibilityIdentifier("player.prevChapterBtn")
                        #endif
                    }

                    #if !os(tvOS)
                    Text(formatDuration(vm.currentTime))
                        .padding(.leading, 6)
                        .accessibilityIdentifier(AccessibilityID.playerCurrentTimeLabel)
                    Spacer()
                    Text(formatDuration(vm.duration))
                        .padding(.trailing, 6)
                        .accessibilityIdentifier("player.durationLabel")
                    #else
                    Spacer()
                    #endif

                    // Next chapter button — only present when the video has chapters
                    if !vm.chapters.isEmpty {
                        #if os(tvOS)
                        tvOverlayControl(
                            highlighted: highlightedControl == .nextChapter,
                            scale: 1.55,
                            shadowRadius: 14,
                            identifier: "player.nextChapterBtn",
                            enabled: vm.hasNextChapter && !vm.isLoading,
                            width: 64,
                            height: 64
                        ) {
                            Image(systemName: AppSymbol.nextChapter)
                                .font(.system(size: 18 * controlScale))
                                .foregroundStyle(vm.hasNextChapter && !vm.isLoading ? .white : .white.opacity(0.3))
                        }
                        #else
                        Button {
                            vm.skipToNextChapter()
                        } label: {
                            Image(systemName: AppSymbol.nextChapter)
                                .font(.system(size: 18 * controlScale))
                                .foregroundStyle(vm.hasNextChapter && !vm.isLoading ? .white : .white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.hasNextChapter || vm.isLoading)
                        .accessibilityIdentifier("player.nextChapterBtn")
                        #endif
                    }

                    #if os(iOS)
                    // Landscape lock button
                    Button {
                        isLandscapeLocked.toggle()
                    } label: {
                        Image(systemName: isLandscapeLocked ? "lock.rotation" : "lock.rotation.open")
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.landscapeLockButton")

                    // Audio-only button
                    Button {
                        vm.toggleAudioOnlyLive()
                        store.settings.audioOnlyMode = vm.isAudioOnlyMode
                    } label: {
                        Image(systemName: store.settings.audioOnlyMode ? "video" : AppSymbol.audioOnly)
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(VFColor.onMedia)
                            .padding(8)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.audioOnlyButton")
                    #endif

                    // Next video button
                    #if os(tvOS)
                    tvOverlayControl(
                        highlighted: highlightedControl == .nextVideo,
                        scale: 1.55,
                        shadowRadius: 14,
                        identifier: AccessibilityID.playerNextButton,
                        enabled: vm.hasNext,
                        width: 64,
                        height: 64
                    ) {
                        Image(systemName: AppSymbol.nextTrack)
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(vm.hasNext ? .white : .white.opacity(0.3))
                    }
                    #else
                    Button {
                        vm.playNext()
                    } label: {
                        Image(systemName: AppSymbol.nextTrack)
                            .font(.system(size: 18 * controlScale))
                            .foregroundStyle(vm.hasNext ? .white : .white.opacity(0.3))
                            #if os(iOS)
                        .padding(8)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                            #endif
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.hasNext)
                    .accessibilityIdentifier(AccessibilityID.playerNextButton)
                    #endif
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                #if os(tvOS)
                .padding(.horizontal, 40)
                #else
                .padding(.horizontal, 20)
                #endif
            }
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            #if os(iOS)
            .allowsHitTesting(false)
            #else
            .contentShape(Rectangle())
            .onTapGesture {
                controlsLog.notice("[menu] gradient background tap — controlsVisible=\(vm.controlsVisible)")
                vm.toggleControls()
            }
            #endif
        )
        #if os(tvOS)
        // Controls overlay is not a focus section — the outer view handles all input.
        .onTapGesture { vm.toggleControls() }
        #endif
    }
}

// MARK: - Control element views

extension PlayerControlsOverlay {

    #if os(tvOS)
    /// The outer player routes remote input; labels avoid tvOS 26's forced Liquid Glass button chrome.
    func tvOverlayControl<Content: View>(
        highlighted: Bool,
        scale: CGFloat,
        shadowOpacity: Double = 0.85,
        shadowRadius: CGFloat,
        identifier: String,
        enabled: Bool = true,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: width, height: height)
            .scaleEffect(highlighted ? scale : 1)
            .shadow(color: highlighted ? .white.opacity(shadowOpacity) : .clear, radius: shadowRadius)
            .animation(.easeInOut(duration: 0.15), value: highlighted)
            .disabled(!enabled)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
    }
    #endif

    // MARK: - Play / Pause

    @ViewBuilder
    var playPauseButton: some View {
        #if os(tvOS)
        tvOverlayControl(
            highlighted: highlightedControl == .playPause,
            scale: 1.6,
            shadowOpacity: 0.65,
            shadowRadius: 8,
            identifier: AccessibilityID.playerPlayPauseButton,
            width: 88,
            height: 88
        ) {
            playPauseIcon
        }
        #else
        Button {
            vm.togglePlayPause()
        } label: {
            playPauseIcon
                .padding(12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(AccessibilityID.playerPlayPauseButton)
        #endif
    }

    var playPauseIcon: some View {
        Image(systemName: vm.videoEnded ? "arrow.counterclockwise" : (vm.isPlaying ? "pause.fill" : "play.fill"))
            .renderingMode(.original)
            .font(.system(size: 42 * controlScale))
            .foregroundStyle(.white)
    }

    // MARK: - Seek buttons

    @ViewBuilder
    func seekButton(symbol: String, seconds: TimeInterval, tvHighlighted: Bool = false) -> some View {
        #if os(tvOS)
        tvOverlayControl(
            highlighted: tvHighlighted,
            scale: 1.55,
            shadowOpacity: 0.6,
            shadowRadius: 7,
            identifier: seconds < 0 ? "player.seekBackButton" : "player.seekForwardButton",
            width: 72,
            height: 72
        ) {
            seekIcon(symbol: symbol)
        }
        #else
        Button {
            vm.seekRelative(seconds: seconds)
        } label: {
            seekIcon(symbol: symbol)
                .padding(12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(seconds < 0 ? "player.seekBackButton" : "player.seekForwardButton")
        #endif
    }

    func seekIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .renderingMode(.original)
            .font(.system(size: 28 * controlScale))
            .foregroundStyle(.white)
    }

    // MARK: - Progress bar

    var progressBar: some View {
        #if os(tvOS)
        tvProgressBar
        #else
        iosProgressBar
        #endif
    }

    var iosProgressBar: some View {
        // Wrap in an outer GeometryReader so the highPriorityGesture below can
        // reference the bar's width.  The gesture is placed on the full-height
        // VStack (tooltip row + track row = 60 pt) so any touch in that area —
        // including the 28 pt invisible tooltip strip above the visible bar — will
        // activate the scrub drag.  Previously the gesture was only on the inner
        // 28 pt track ZStack, which meant touches on the empty tooltip row were
        // silently swallowed without triggering the seek.
        GeometryReader { outerGeo in
            let hPad: CGFloat = 20
            let trackW = outerGeo.size.width - hPad * 2

            VStack(spacing: 4) {
                // Tooltip row — always occupies space so layout doesn't jump
                GeometryReader { geo in
                    if vm.isScrubbing && vm.duration > 0 {
                        let fraction = CGFloat(vm.scrubTime / vm.duration)
                        let thumbX = hPad + trackW * fraction
                        let chapterAtScrub = vm.chapters.last(where: { $0.startTime <= vm.scrubTime })
                        let labelW: CGFloat = chapterAtScrub != nil ? min(outerGeo.size.width * 0.5, 180) : 64
                        let clampedX = min(max(thumbX, hPad + labelW / 2), outerGeo.size.width - hPad - labelW / 2)

                        VStack(spacing: 2) {
                            if let chapter = chapterAtScrub {
                                Text(chapter.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Text(formatDuration(vm.scrubTime))
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        .frame(width: labelW)
                        .position(x: clampedX, y: geo.size.height / 2)
                    }
                }
                .frame(height: 28)

                // Track + slider row (custom — fully transparent thumb and track)
                GeometryReader { geo in
                    let time = vm.isScrubbing ? vm.scrubTime : vm.currentTime
                    let progress = vm.duration > 0 ? CGFloat(time / vm.duration) : 0
                    let thumbX = hPad + trackW * progress

                    ZStack {
                        // Background track
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 4)
                            .padding(.horizontal, hPad)

                        // Progress fill
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(Color.red.opacity(0.5))
                                .frame(width: max(thumbX - hPad, 0), height: 4)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, hPad)

                        // Thumb
                        Circle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .position(x: thumbX, y: geo.size.height / 2)
                    }
                    .overlay(sponsorBlockMarkers)
                    .overlay(chapterMarkers)
                }
                .frame(height: 28)
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            // highPriorityGesture on the full VStack (tooltip + track, 60 pt total)
            // ensures the seek-bar drag beats any child-view tap gestures (e.g.
            // chapter-marker hit areas) and activates even when the touch lands on
            // the invisible tooltip strip above the visible progress bar.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max((value.location.x - hPad) / trackW, 0), 1)
                        if !vm.isScrubbing { vm.beginScrubbing() }
                        vm.updateScrub(to: Double(fraction) * vm.duration)
                    }
                    .onEnded { _ in vm.commitScrub() }
            )
            #endif
        }
        .frame(height: 60)
        .accessibilityIdentifier(AccessibilityID.playerProgressBar)
    }

    // Chapter tick marks on the progress bar — small white notches at each chapter boundary.
    // Each tick has a 24×44 pt transparent tap area so the user can tap to jump to it.
}
