import SmartTubeIOSCore
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

let playerMenuLog = ViewModelLogger(category: "PlayerMenu")

// Measures the natural height of moreMenuItems so the sheet hugs its content
// instead of always expanding to moreMenuMaxHeight.
private struct MoreMenuContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The More menu slides up and fades; with Reduce Motion it only fades.
private struct MoreMenuTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - PlayerView overlay sheets
//
// Pure-SwiftUI overlays rendered inside the player's ZStack so no UIKit
// sheet presentation fires onDisappear and tears down playback.
//
// Includes:
//   • moreMenuOverlay      — all top-bar actions + share/download
//   • loadComments()       — async comment fetching
//   • descriptionAttributedString(_:) — URL linkification helper

extension PlayerView {

    // MARK: - Overlay stack

    /// All picker / sheet overlays rendered inside the player ZStack.
    /// Consolidating them here caps the 8-branch ModifiedContent type tree in a single
    /// compiled function, reducing __swift5_typeref size in the binary.
    /// The option panels are here on tvOS only; iOS and macOS present them natively (`playerContentView`).
    @ViewBuilder var overlayStack: some View {
        #if !os(iOS)
        // The container animates both the insertion and the removal; Reduce Motion fades instead of sliding.
        ZStack {
            if showMoreMenu {
                moreMenuOverlay
                    .modifier(MoreMenuTransition())
            }
        }
        .animation(.easeOut(duration: VFMotion.standard), value: showMoreMenu)
        #endif
        #if os(tvOS)
        tvOptionPanels
        #endif
    }

    // MARK: - More menu overlay

    /// Pure-SwiftUI bottom sheet combining all top-bar controls + Share/Download.
    /// Rendered inside the player's ZStack so no UIKit sheet presentation
    /// fires onDisappear and teardowns the action sheet mid-animation.
    var moreMenuOverlay: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        playerMenuLog.notice(
            "[moreMenu] rendering — video=\(currentVideo.id) availableFormats=\(vm.availableFormats.count) isSignedIn=\(authService.isSignedIn)"
        )
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    playerMenuLog.notice("[moreMenu] background tap — dismissing")
                    showMoreMenu = false
                }

            // ScrollView capped at moreMenuMaxHeight to avoid GeometryReader/containerRelativeFrame
            // feedback loops that crash SwiftUI's AttributeGraph (SIGSEGV/SIGBUS recursion).
            // Previously this used ViewThatFits with duplicate moreMenuItems references; that pattern
            // causes AttributeGraph EXC_BAD_ACCESS when SwiftUI evaluates both alternatives and the
            // shared @ViewBuilder identity produces a graph cycle. Using a single ScrollView path
            // is safe because .frame(maxHeight:) already caps the height appropriately.
            ScrollView {
                moreMenuItems
                    // Measure the VStack's natural height one pass before the
                    // containing frame is applied, so the sheet hugs its content.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MoreMenuContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuScrollView)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
            .onPreferenceChange(MoreMenuContentHeightKey.self) { moreMenuContentHeight = $0 }
            // Height = natural content height capped at moreMenuMaxHeight.
            // Falls back to moreMenuMaxHeight on the first render (before the
            // preference arrives), then snaps to the correct size on the next pass.
            .frame(
                maxWidth: moreMenuPortraitWidth,
                maxHeight: moreMenuContentHeight > 0 ? min(moreMenuContentHeight, moreMenuMaxHeight) : moreMenuMaxHeight
            )
            #if !os(iOS)
            // Menu button on tvOS, Escape on macOS.
            .onExitCommand {
                playerMenuLog.notice("[moreMenu] onExitCommand fired — dismissing")
                showMoreMenu = false
            }
            #endif
            #if os(tvOS)
            // Native SwiftUI focus handles D-pad navigation via the .focused() bindings
            // on each row button. onMoveCommand was removed because it caused a double-step
            // bug: both onMoveCommand and the native focus engine responded to the same
            // D-pad event, advancing focus twice per press.
            .onAppear {
                playerMenuLog.notice("[moreMenu] overlay appeared — native tvOS focus via .focused() bindings")
            }
            .onDisappear {
                playerMenuLog.notice("[moreMenu] overlay disappeared")
            }
            #endif
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.horizontal, moreMenuAdditionalHorizontalPadding)
            .safeAreaPadding(.bottom)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        #if os(tvOS)
        .focusScope(moreMenuNamespace)
        #endif
    }

    @ViewBuilder private var moreMenuItems: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        VStack(spacing: 0) {
            // Centered title header
            VStack(spacing: 2) {
                OfflineSavedTitle(title: currentVideo.title, videoID: currentVideo.id)
                    .font(.subheadline).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !currentVideo.channelTitle.isEmpty {
                    Text(currentVideo.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            moreMenuChannelRow
            #if os(tvOS)
            moreMenuSpeedRow
            moreMenuQualityRow
            #endif
            moreMenuLikeDislikeRow
            moreMenuShareRow
            moreMenuSleepTimerRow
            #if os(tvOS)
            moreMenuAudioOnlyRow
            #endif
            moreMenuQueueShuffleRow
            moreMenuDownloadRow
            moreMenuCaptionsRow
            moreMenuAudioTrackRow
            moreMenuDescriptionRow
            moreMenuCommentsRow
            moreMenuStatsForNerdsRow
            moreMenuCancelRow
        }
        .frame(maxWidth: .infinity)
        .font(.subheadline)
    }

    private var moreMenuMaxHeight: CGFloat {
        #if os(iOS)
        verticalSizeClass == .compact ? 320 : 440
        #else
        520
        #endif
    }

    private var moreMenuAdditionalHorizontalPadding: CGFloat {
        #if os(iOS)
        vm.isLandscape ? 36 : 0
        #else
        0
        #endif
    }

    var moreMenuPortraitWidth: CGFloat {
        #if os(iOS)
        if let bounds = playerState.playerHostView.window?.bounds {
            min(bounds.width, bounds.height) * 0.8
        } else {
            .infinity
        }
        #else
        .infinity
        #endif
    }

    // MARK: - More menu rows
    //
    // Each row is a @ViewBuilder var so its type tree is a separate compiled function,
    // reducing moreMenuOverlay from one ~10.5 KB symbol to many ~1 KB symbols.

    @ViewBuilder private var moreMenuSpeedRow: some View {
        Button {
            playerMenuLog.notice("[moreMenu] Speed row tapped — closing moreMenu, opening speedPicker")
            showMoreMenu = false
            showSpeedPicker = true
        } label: {
            HStack {
                Label("Playback Speed", systemImage: AppSymbol.speedometer)
                Spacer()
                Text(
                    store.settings.playbackSpeed == 1.0
                        ? "Normal"
                        : "\(store.settings.playbackSpeed, specifier: "%.2g")×"
                )
                .foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuSpeedRow)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .speed)
        .prefersDefaultFocus(in: moreMenuNamespace)
        #endif
        Divider()
    }

    #if os(tvOS)
    @ViewBuilder private var moreMenuQualityRow: some View {
        if !vm.availableFormats.isEmpty {
            Button {
                playerMenuLog.notice("[moreMenu] Quality row tapped — closing moreMenu, opening qualityPicker")
                showMoreMenu = false
                showQualityPicker = true
            } label: {
                HStack {
                    Label("Quality", systemImage: AppSymbol.videoQuality)
                    Spacer()
                    Text(
                        vm.selectedFormat?.qualityLabel
                            ?? (vm.pendingQualityLabel.isEmpty ? "Auto" : vm.pendingQualityLabel)
                    )
                    .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .playerMenuRowButtonStyle()
            .foregroundStyle(.primary)
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuQualityRow)
            .focused($moreMenuFocusedRow, equals: .quality)
            Divider()
        }
    }
    #endif

    /// Local videos need access to the translation language picker even before a language is chosen.
    private var shouldShowAudioTrackInMoreMenu: Bool {
        let hasChoice = vm.hasAudioOptions
        #if os(tvOS)
        return hasChoice
        #else
        return hasChoice && !vm.controlsVisible
        #endif
    }

    @ViewBuilder var moreMenuLikeDislikeRow: some View {
        if authService.isSignedIn {
            HStack(spacing: 0) {
                Button {
                    vm.like()
                    showMoreMenu = false
                } label: {
                    Label(
                        vm.likeStatus == .like ? "Liked" : "Like",
                        systemImage: vm.likeStatus == .like
                            ? "\(AppSymbol.thumbsUp).fill" : AppSymbol.thumbsUp
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(vm.likeStatus == .like ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .playerMenuRowButtonStyle()
                .accessibilityIdentifier(AccessibilityID.playerMoreMenuLikeRow)
                #if os(tvOS)
                .focused($moreMenuFocusedRow, equals: .like)
                #endif
                Divider().frame(height: 44)
                Button {
                    vm.dislike()
                    showMoreMenu = false
                } label: {
                    Label(
                        vm.likeStatus == .dislike ? "Disliked" : "Dislike",
                        systemImage: vm.likeStatus == .dislike
                            ? "\(AppSymbol.thumbsDown).fill" : AppSymbol.thumbsDown
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(vm.likeStatus == .dislike ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .playerMenuRowButtonStyle()
                .accessibilityIdentifier(AccessibilityID.playerMoreMenuDislikeRow)
                #if os(tvOS)
                .focused($moreMenuFocusedRow, equals: .dislike)
                #endif
            }
            #if !os(iOS)
            Divider()
            #endif
        }
    }

    @ViewBuilder var moreMenuShareRow: some View {
        #if os(iOS)
        Button {
            if let url = (vm.playerInfo?.video ?? video).shareURL {
                openMoreMenuDestination(.share(url))
            } else {
                showMoreMenu = false
            }
        } label: {
            Label("Share", systemImage: AppSymbol.share)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuShareRow)
        #endif
    }

    @ViewBuilder var moreMenuSleepTimerRow: some View {
        Button {
            playerMenuLog.notice("[moreMenu] Sleep Timer row tapped — closing moreMenu, opening sleepTimerPicker")
            openMoreMenuDestination(.sleepTimer)
        } label: {
            HStack {
                Label {
                    Text("Sleep Timer", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.sleepTimer)
                }
                Spacer()
                if let fireDate = vm.sleepTimer.fireDate {
                    Text(timerInterval: Date.now...max(fireDate, .now), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("Off", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuSleepTimerRow)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .sleepTimer)
        #endif
        #if !os(iOS)
        Divider()
        #endif
    }

    @ViewBuilder private var moreMenuAudioOnlyRow: some View {
        Button {
            playerMenuLog.notice(
                "[moreMenu] Audio-Only row tapped — toggling audioOnlyMode: \(store.settings.audioOnlyMode) → \(!store.settings.audioOnlyMode)"
            )
            vm.toggleAudioOnlyLive()
            store.settings.audioOnlyMode = vm.isAudioOnlyMode
            showMoreMenu = false
        } label: {
            HStack {
                Label {
                    Text("Audio-Only", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.audioOnly)
                }
                Spacer()
                if store.settings.audioOnlyMode {
                    Image(systemName: AppSymbol.checkmark)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityAddTraits(store.settings.audioOnlyMode ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuAudioOnlyRow)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .audioOnly)
        #endif
        Divider()
    }

    @ViewBuilder var moreMenuQueueShuffleRow: some View {
        if (vm.playerInfo?.video ?? video).playlistId == CurrentQueueStore.playlistID {
            Button {
                playerMenuLog.notice(
                    "[moreMenu] Queue Shuffle row tapped — toggling queueShuffleEnabled: \(store.settings.queueShuffleEnabled) → \(!store.settings.queueShuffleEnabled)"
                )
                store.settings.queueShuffleEnabled.toggle()
                showMoreMenu = false
            } label: {
                HStack {
                    Label {
                        Text("Shuffle Queue", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.shuffle)
                    }
                    Spacer()
                    if store.settings.queueShuffleEnabled {
                        Image(systemName: AppSymbol.checkmark)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .playerMenuRowButtonStyle()
            .foregroundStyle(.primary)
            .accessibilityAddTraits(store.settings.queueShuffleEnabled ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuQueueShuffleRow)
            #if os(tvOS)
            .focused($moreMenuFocusedRow, equals: .queueShuffle)
            #endif
            #if !os(iOS)
            Divider()
            #endif
        }
    }

    @ViewBuilder var moreMenuDownloadRow: some View {
        // iOS and macOS show Offline in the quick-access row; tvOS has no such row.
        #if os(tvOS)
        OfflineWatchButton(video: vm.currentVideo ?? video) {
            openMoreMenuDestination(.offline(vm.currentVideo ?? video))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        Divider()
        #endif
        #if !os(tvOS) && ENABLE_DOWNLOADS
        Button {
            showMoreMenu = false
            downloadService.download(video: vm.playerInfo?.video ?? video)
        } label: {
            Group {
                if downloadService.state.isActive {
                    Label("Downloading…", systemImage: AppSymbol.download)
                } else {
                    Label("Download to Gallery", systemImage: AppSymbol.download)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .disabled(downloadService.state.isActive)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuDownloadButton)
        #if !os(iOS)
        Divider()
        #endif
        #endif
    }

    @ViewBuilder var moreMenuCaptionsRow: some View {
        if !vm.availableCaptions.isEmpty {
            Button {
                openMoreMenuDestination(.captions)
            } label: {
                HStack {
                    Label("Captions", systemImage: AppSymbol.captions)
                    Spacer()
                    Text(
                        vm.selectedCaption.map {
                            $0.isAutoGenerated ? "\($0.name) (auto)" : $0.name
                        } ?? "Off"
                    )
                    .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .playerMenuRowButtonStyle()
            .foregroundStyle(.primary)
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuCaptionsRow)
            #if os(tvOS)
            .focused($moreMenuFocusedRow, equals: .captions)
            #endif
            #if !os(iOS)
            Divider()
            #endif
        }
    }

    @ViewBuilder var moreMenuAudioTrackRow: some View {
        if shouldShowAudioTrackInMoreMenu {
            Button {
                openMoreMenuDestination(.audioTrack)
            } label: {
                HStack {
                    Label("Audio Track", systemImage: AppSymbol.audioTrack)
                    Spacer()
                    Text(
                        vm.selectedAudioTrack.map {
                            $0.isOriginal ? "\($0.name) (Original)" : $0.name
                        } ?? "Auto"
                    )
                    .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .playerMenuRowButtonStyle()
            .foregroundStyle(.primary)
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuAudioTrackRow)
            #if os(tvOS)
            .focused($moreMenuFocusedRow, equals: .audioTrack)
            #endif
            #if !os(iOS)
            Divider()
            #endif
        }
    }

    /// Always offered: the sheet also shows the full title and channel, which the one-line title bar truncates,
    /// and says "No description available." when there is none.
    @ViewBuilder var moreMenuDescriptionRow: some View {
        Button {
            openMoreMenuDestination(.description)
        } label: {
            Label("Description", systemImage: AppSymbol.description)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuDescriptionRow)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .description)
        #endif
        #if !os(iOS)
        Divider()
        #endif
    }

    @ViewBuilder var moreMenuCommentsRow: some View {
        Button {
            openMoreMenuDestination(.comments)
        } label: {
            Label("Comments", systemImage: AppSymbol.comments)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuCommentsRow)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .comments)
        #endif
        #if !os(iOS)
        Divider()
        #endif
    }

    @ViewBuilder var moreMenuStatsForNerdsRow: some View {
        Button {
            vm.toggleStatsForNerds()
            showMoreMenu = false
        } label: {
            HStack {
                Label("Stats for Nerds", systemImage: AppSymbol.stats)
                Spacer()
                if vm.statsForNerdsVisible {
                    Image(systemName: AppSymbol.checkmark)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityAddTraits(vm.statsForNerdsVisible ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuStatsForNerds)
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .statsForNerds)
        #endif
        #if !os(iOS)
        Divider()
        #endif
    }

    @ViewBuilder private var moreMenuCancelRow: some View {
        Button {
            showMoreMenu = false
        } label: {
            Text("Cancel")
                .frame(maxWidth: .infinity)
                .padding()
                .fontWeight(.semibold)
                .contentShape(Rectangle())
        }
        .playerMenuRowButtonStyle()
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuCancelButton)
        #if os(macOS)
        .keyboardShortcut(.cancelAction)
        #endif
        #if os(tvOS)
        .focused($moreMenuFocusedRow, equals: .cancel)
        #endif
    }
}

extension View {
    /// The More menu's row button style: plain, and on tvOS a high-contrast focus platter.
    func playerMenuRowButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(PlayerMenuRowButtonStyle())
        #else
        buttonStyle(.plain)
        #endif
    }
}
