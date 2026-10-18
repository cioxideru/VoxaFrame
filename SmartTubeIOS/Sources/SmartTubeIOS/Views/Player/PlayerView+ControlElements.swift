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
//
// iPhone, iPad and Mac (VF/Player, VF/Transport): top bar, then previous · back · play/pause · forward · next,
// then the timeline, time and chapter row and the quick settings. Every glyph is `onMedia` on glass over the
// scrim, so it reads on any frame; an active toggle is inverted, not only tinted. tvOS keeps its own layout
// because its remote navigation (`tvNextControl`) is built on those rows.

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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var vm: PlaybackViewModel { playerState.vm }
    #else
    let vm: PlaybackViewModel
    #endif
    #if !os(tvOS)
    @Binding var showQualityPicker: Bool
    @Binding var showSpeedPicker: Bool
    @Binding var showAudioTrackPicker: Bool
    @Binding var showSleepTimerPicker: Bool
    /// The bottom bar's height, which the captions keep clear of.
    @Binding var bottomBarHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    #if os(tvOS)
    @Binding var highlightedControl: PlayerView.TVPlayerControl?
    #endif
    @Environment(SettingsStore.self) var store
    @Environment(\.dismiss) var dismiss

    #if os(tvOS)
    var body: some View {
        VStack {
            // Top bar: back + title
            HStack {
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
                        .foregroundStyle(VFColor.onMedia)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.playerInfo?.video.title ?? video.title)
                        .font(.headline)
                        .foregroundStyle(VFColor.onMedia)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.playerTitleLabel)
                    let channelId = vm.playerInfo?.video.channelId ?? video.channelId
                    tvOverlayControl(
                        highlighted: highlightedControl == .channel,
                        scale: 1.5,
                        shadowRadius: 12,
                        identifier: "player.channelName",
                        enabled: channelId?.isEmpty == false
                    ) {
                        Text(vm.playerInfo?.video.channelTitle ?? video.channelTitle)
                            .font(.subheadline)
                            .foregroundStyle(VFColor.onMedia.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                Spacer()
                videoScaleButton
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
                        .foregroundStyle(VFColor.onMedia)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)

            Spacer()

            // Centre: rewind / play-pause / forward
            HStack(spacing: 40) {
                seekButton(
                    symbol: "gobackward.\(store.settings.seekBackSeconds)",
                    seconds: -Double(store.settings.seekBackSeconds),
                    tvHighlighted: highlightedControl == .seekBack)
                playPauseButton
                seekButton(
                    symbol: "goforward.\(store.settings.seekForwardSeconds)",
                    seconds: Double(store.settings.seekForwardSeconds),
                    tvHighlighted: highlightedControl == .seekForward)
            }
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.3 : 1)

            Spacer()

            // Bottom: progress bar + prev/next
            VStack(spacing: 8) {
                currentChapterTitle
                progressBar
                HStack {
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
                            .foregroundStyle(VFColor.onMedia.opacity(vm.hasPrevious && !vm.isLoading ? 1 : 0.3))
                    }
                    if !vm.chapters.isEmpty {
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
                                .foregroundStyle(
                                    VFColor.onMedia.opacity(vm.hasPreviousChapter && !vm.isLoading ? 1 : 0.3))
                        }
                    }
                    Spacer()
                    if !vm.chapters.isEmpty {
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
                                .foregroundStyle(VFColor.onMedia.opacity(vm.hasNextChapter && !vm.isLoading ? 1 : 0.3))
                        }
                    }
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
                            .foregroundStyle(VFColor.onMedia.opacity(vm.hasNext ? 1 : 0.3))
                    }
                }
                .font(.caption)
                .foregroundStyle(VFColor.onMedia.opacity(0.8))
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 20)
            // The timeline and its buttons on a solid scrim, so the unplayed track keeps 3:1 over a white frame.
            .playerBarScrim(fadingDown: false)
        }
        .background(
            scrimGradient
                .contentShape(Rectangle())
                .onTapGesture {
                    controlsLog.notice("[menu] gradient background tap — controlsVisible=\(vm.controlsVisible)")
                    vm.toggleControls()
                }
        )
        // Controls overlay is not a focus section — the outer view handles all input.
        .onTapGesture { vm.toggleControls() }
    }
    #else
    var body: some View {
        // The safe area is ignored by the caller so each bar's scrim reaches the edges; the bars keep their
        // content out of the notch and home indicator.
        VStack(spacing: 0) {
            topBar
                .padding(.leading, safeAreaInsets.leading)
                .padding(.trailing, safeAreaInsets.trailing)
                .playerBarScrim(fadingDown: true)
            Spacer(minLength: VFSpace.s8)
            transportRow
            Spacer(minLength: VFSpace.s8)
            bottomBar
                .padding(.leading, safeAreaInsets.leading)
                .padding(.trailing, safeAreaInsets.trailing)
                .playerBarScrim(fadingDown: false)
                // Captions sit above whatever height the bar has in this layout and text size.
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { bottomBarHeight = $0 })
        }
        // Controls always sit on dark media, whatever the app's appearance, so glass and fallbacks resolve dark.
        .environment(\.colorScheme, .dark)
        .background { tapSurface }
    }

    /// macOS: a click on the video outside the controls hides them. iOS uses the player's own tap gesture.
    @ViewBuilder private var tapSurface: some View {
        #if os(macOS)
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                controlsLog.notice("[menu] background tap — controlsVisible=\(vm.controlsVisible)")
                vm.toggleControls()
            }
        #endif
    }
    #endif
}

// MARK: - iPhone, iPad and Mac bars

#if !os(tvOS)
extension PlayerControlsOverlay {

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: VFSpace.s8) {
            Button {
                #if os(iOS)
                if store.settings.miniPlayerEnabled { playerState.minimize() } else { playerState.stop() }
                #else
                vm.stop()
                withAnimation(.none) { dismiss() }
                #endif
            } label: {
                Image(systemName: backSymbol)
                    .font(.system(size: 18 * controlScale, weight: .semibold))
                    .playerMediaControl(diameter: VFTarget.touch * controlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier(AccessibilityID.playerBackButton)
            titleBlock
            Spacer(minLength: VFSpace.s8)
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
                        .playerMediaControl(diameter: VFTarget.touch * controlScale, isActive: isPiPActive)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Picture in Picture", bundle: .module))
                .accessibilityAddTraits(isPiPActive ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityID.playerPiPButton)
            }
            // AirPlay route picker: draws its own glyph and takes touches across the whole disc.
            AirPlayRoutePickerView()
                .playerMediaControl(diameter: VFTarget.touch * controlScale)
                .accessibilityIdentifier(AccessibilityID.playerAirPlayButton)
            #endif
            Button {
                controlsLog.notice(
                    "[menu] ... button tapped — controlsVisible=\(vm.controlsVisible) showMoreMenu=\(showMoreMenu)")
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18 * controlScale, weight: .semibold))
                    .playerMediaControl(diameter: VFTarget.touch * controlScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("More", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.playerMoreButton)
            .playerOptionPanelTrigger(.more)
        }
        .padding(.horizontal, VFSpace.s20)
        .padding(.top, max(safeAreaInsets.top, VFSpace.s20))
    }

    private var backSymbol: String {
        #if os(iOS)
        store.settings.miniPlayerEnabled ? AppSymbol.chevronDown : AppSymbol.xmark
        #else
        AppSymbol.chevronLeft
        #endif
    }

    private var backLabel: Text {
        #if os(iOS)
        if store.settings.miniPlayerEnabled { return Text("Minimize", bundle: .module) }
        return Text("Close", bundle: .module)
        #else
        return Text("Back", bundle: .module)
        #endif
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vm.playerInfo?.video.title ?? video.title)
                .font(.headline)
                .foregroundStyle(VFColor.onMedia)
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityID.playerTitleLabel)
            let channelId = vm.playerInfo?.video.channelId ?? video.channelId
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
                Text(vm.playerInfo?.video.channelTitle ?? video.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(VFColor.onMedia.opacity(0.8))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.playerChannelName)
            .disabled(channelId == nil || channelId?.isEmpty == true)
        }
    }

    // MARK: Transport

    private var transportRow: some View {
        HStack(spacing: VFSpace.s24) {
            mediaButton(
                symbol: AppSymbol.previousTrack, label: Text("Previous Video", bundle: .module),
                identifier: "player.prevBtn", enabled: vm.hasPrevious && !vm.isLoading
            ) { vm.playPrevious() }
            HStack(spacing: VFSpace.s24) {
                seekButton(
                    symbol: "gobackward.\(store.settings.seekBackSeconds)",
                    seconds: -Double(store.settings.seekBackSeconds))
                playPauseButton
                seekButton(
                    symbol: "goforward.\(store.settings.seekForwardSeconds)",
                    seconds: Double(store.settings.seekForwardSeconds))
            }
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.35 : 1)
            mediaButton(
                symbol: AppSymbol.nextTrack, label: Text("Next Video", bundle: .module),
                identifier: AccessibilityID.playerNextButton, enabled: vm.hasNext
            ) { vm.playNext() }
        }
    }

    /// A round transport button; an unavailable one stays visible and disabled rather than disappearing.
    private func mediaButton(
        symbol: String, label: Text, identifier: String, enabled: Bool, diameter: CGFloat = 52,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20 * controlScale))
                .playerMediaControl(diameter: diameter * controlScale)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Bottom bar

    /// Timeline, then time and buttons, then the setting pills. In a landscape iPhone the time, pills and buttons
    /// share one row, so the bar leaves the picture (and the captions above it) as much room as it can. At
    /// accessibility text sizes they keep two rows and the pills scroll sideways instead of being cut.
    private var bottomBar: some View {
        VStack(spacing: VFSpace.s8) {
            currentChapterTitle
            progressBar
            if isCompactHeight && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: VFSpace.s12) {
                    timeLabel
                    quickAccessButtons
                    Spacer(minLength: VFSpace.s8)
                    rowButtons
                }
                .padding(.horizontal, VFSpace.s20)
            } else {
                HStack(spacing: VFSpace.s8) {
                    timeLabel
                    Spacer(minLength: VFSpace.s8)
                    rowButtons
                }
                .padding(.horizontal, VFSpace.s20)
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView(.horizontal, showsIndicators: false) {
                        quickAccessButtons.padding(.horizontal, VFSpace.s20)
                    }
                } else {
                    quickAccessButtons
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VFSpace.s20)
                }
            }
        }
        .padding(.bottom, max(safeAreaInsets.bottom, VFSpace.s16))
    }

    private var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var timeLabel: some View {
        HStack(spacing: VFSpace.s4) {
            Text(formatDuration(vm.currentTime))
                .accessibilityIdentifier(AccessibilityID.playerCurrentTimeLabel)
            Text(verbatim: "/")  // verbatim: a separator between two times, the same in every language
                .accessibilityHidden(true)
            Text(formatDuration(vm.duration))
                .accessibilityIdentifier(AccessibilityID.playerDurationLabel)
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(VFColor.onMedia)
        .fixedSize()
    }

    /// Chapter steps, then the iPhone and iPad toggles.
    private var rowButtons: some View {
        HStack(spacing: VFSpace.s8) {
            // Chapter buttons only exist when the video has chapters.
            if !vm.chapters.isEmpty {
                mediaButton(
                    symbol: AppSymbol.previousChapter, label: Text("Previous Chapter", bundle: .module),
                    identifier: "player.prevChapterBtn", enabled: vm.hasPreviousChapter && !vm.isLoading,
                    diameter: VFTarget.touch
                ) { vm.skipToPreviousChapter() }
                mediaButton(
                    symbol: AppSymbol.nextChapter, label: Text("Next Chapter", bundle: .module),
                    identifier: "player.nextChapterBtn", enabled: vm.hasNextChapter && !vm.isLoading,
                    diameter: VFTarget.touch
                ) { vm.skipToNextChapter() }
            }
            #if os(iOS)
            Button {
                isLandscapeLocked.toggle()
            } label: {
                Image(systemName: isLandscapeLocked ? "lock.rotation" : "lock.rotation.open")
                    .font(.system(size: 18 * controlScale))
                    .playerMediaControl(diameter: VFTarget.touch * controlScale, isActive: isLandscapeLocked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Landscape Lock", bundle: .module))
            .accessibilityAddTraits(isLandscapeLocked ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.playerLandscapeLockButton)

            Button {
                vm.toggleAudioOnlyLive()
                store.settings.audioOnlyMode = vm.isAudioOnlyMode
            } label: {
                Image(systemName: AppSymbol.audioOnly)
                    .font(.system(size: 18 * controlScale))
                    .playerMediaControl(
                        diameter: VFTarget.touch * controlScale, isActive: store.settings.audioOnlyMode)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Audio-Only", bundle: .module))
            .accessibilityAddTraits(store.settings.audioOnlyMode ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.playerAudioOnlyButton)
            #endif
        }
    }
}
#endif

extension PlayerControlsOverlay {

    // MARK: Shared parts

    @ViewBuilder private var currentChapterTitle: some View {
        // Current chapter title — shown whenever chapters are available
        if let chapter = vm.currentChapter {
            Text(chapter.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VFColor.onMedia.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                .vfAnimation(value: chapter.title)
        }
    }

    #if os(tvOS)
    /// The scrim behind the TV controls: darkest at the top and bottom, where the text and buttons are.
    private var scrimGradient: some View {
        LinearGradient(
            colors: [VFColor.scrim, .clear, .clear, VFColor.scrim],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    #endif
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
                .playerMediaControl(diameter: 72 * controlScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playPauseLabel)
        .accessibilityIdentifier(AccessibilityID.playerPlayPauseButton)
        #endif
    }

    var playPauseIcon: some View {
        Image(systemName: vm.videoEnded ? "arrow.counterclockwise" : (vm.isPlaying ? "pause.fill" : "play.fill"))
            .renderingMode(.original)
            .font(.system(size: 34 * controlScale))
            .foregroundStyle(VFColor.onMedia)
    }

    /// Names the action, as the glyph does: Replay after the end, otherwise Pause or Play.
    private var playPauseLabel: Text {
        if vm.videoEnded { return Text("Replay", bundle: .module) }
        return vm.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module)
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
        // The interval in the glyph and the label comes from Settings, never a drawn constant.
        let interval = Int(abs(seconds))
        Button {
            vm.seekRelative(seconds: seconds)
        } label: {
            seekIcon(symbol: symbol)
                .playerMediaControl(diameter: 52 * controlScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            seconds < 0
                ? Text("Back \(interval) seconds", bundle: .module)
                : Text("Forward \(interval) seconds", bundle: .module)
        )
        .accessibilityIdentifier(seconds < 0 ? "player.seekBackButton" : "player.seekForwardButton")
        #endif
    }

    func seekIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .renderingMode(.original)
            .font(.system(size: 24 * controlScale))
            .foregroundStyle(VFColor.onMedia)
    }

    // MARK: - Progress bar

    var progressBar: some View {
        #if os(tvOS)
        tvProgressBar
        #else
        iosProgressBar
        #endif
    }
}
