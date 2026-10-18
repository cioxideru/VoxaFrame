#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

/// Tabs of the Mac player inspector.
enum PlayerInspectorTab: Hashable {
    case upNext, description, comments
}

/// What the Up next list depends on: the playing video and, for a Current Queue item, its position,
/// so consecutive duplicates ([A, A, B]) still refresh. Mirrors the queue check in `playNext()`.
struct UpNextSource: Hashable {
    let videoID: String?
    let queueIndex: Int?

    init(_ video: Video?) {
        videoID = video?.id
        queueIndex = video?.playlistId == CurrentQueueStore.playlistID ? video?.playlistIndex : nil
    }

    /// The queue items `playNext()` walks after this position; empty outside the queue.
    func remainingQueue(in store: CurrentQueueStore = .shared) async -> [Video] {
        guard let queueIndex else { return [] }
        return await store.remainingVideos(after: queueIndex)
    }
}

/// Visibility of the focused window's player inspector; set by `PlayerView`,
/// read by the View menu item in `MacWindowCommands`, so menu and toolbar share one state.
private struct PlayerInspectorVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var playerInspectorVisible: Binding<Bool>? {
        get { self[PlayerInspectorVisibleKey.self] }
        set { self[PlayerInspectorVisibleKey.self] = newValue }
    }
}

/// Title of the menu item and toolbar button that show or hide the player panel.
func playerInspectorToggleTitle(isVisible: Bool) -> String {
    isVisible
        ? String(localized: "Hide Inspector", bundle: .module)
        : String(localized: "Show Inspector", bundle: .module)
}

// MARK: - Mac player layout
//
// The player sits in the window's content area with "Up next", "Description" and "Comments" in an
// inspector beside it. Width and full screen only suppress presentation, preserving `showInspector`.

extension PlayerView {
    /// The playing video, which changes on Next/Previous and Up next while `video` stays the opened one.
    private var activeVideoID: String { vm.currentVideo?.id ?? video.id }

    var macPlayerLayout: some View {
        playerContentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(MacPlayerInteraction(vm: vm, hasOpenPanel: macHasOpenPanel, focused: $macPlayerFocused))
            .inspector(
                isPresented: inspectorPresentation
            ) {
                inspectorPanel
                    .inspectorColumnWidth(ideal: VFMacWindow.inspectorWidth)
                    .toolbar {
                        ToolbarItem {
                            let title = playerInspectorToggleTitle(isVisible: inspectorPresentation.wrappedValue)
                            Button {
                                showInspector.toggle()
                            } label: {
                                Label(title, systemImage: AppSymbol.inspector)
                            }
                            .disabled(!macWindow.allowsInspector)
                            .help(title)
                            .accessibilityIdentifier(AccessibilityID.playerInspectorToggle)
                        }
                    }
            }
            .focusedSceneValue(\.playerInspectorVisible, macWindow.allowsInspector ? inspectorPresentation : nil)
            .onAppear { macWindow.setPlayer(ObjectIdentifier(vm), visible: true) }
            .onDisappear { macWindow.setPlayer(ObjectIdentifier(vm), visible: false) }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: { showInspector && macWindow.allowsInspector },
            set: { if macWindow.allowsInspector { showInspector = $0 } }
        )
    }

    private var macHasOpenPanel: Bool {
        showMoreMenu || showSpeedPicker || showQualityPicker || showCaptionPicker || showAudioTrackPicker
            || showSleepTimerPicker || showDescriptionSheet || showCommentsSheet || offlineDownloadVideo != nil
    }

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Inspector", bundle: .module), selection: $inspectorTab) {
                Text("Up next", bundle: .module).tag(PlayerInspectorTab.upNext)
                Text("Description", bundle: .module).tag(PlayerInspectorTab.description)
                Text("Comments", bundle: .module).tag(PlayerInspectorTab.comments)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(VFSpace.s12)
            Divider()
            Group {
                switch inspectorTab {
                case .upNext: ScrollView { upNextList }
                case .description: ScrollView { descriptionContent }
                case .comments:
                    // Never show another video's list while this one's request is pending.
                    let isCurrent = vm.comments.videoId == activeVideoID
                    CommentsList(
                        comments: isCurrent ? vm.comments.comments : [],
                        isLoading: !isCurrent || vm.comments.isLoading
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Keyed by the playing video, so Next with Comments open loads the new video's comments.
        .onChange(of: inspectorTab == .comments ? activeVideoID : nil, initial: true) { _, videoID in
            if let videoID { vm.comments.load(videoId: videoID) }
        }
        // Same order as `playNext()`: the rest of the Current Queue, otherwise suggestions.
        .task(id: UpNextSource(vm.currentVideo)) {
            let queue = await UpNextSource(vm.currentVideo).remainingQueue()
            if !Task.isCancelled { upNextQueue = queue }
        }
    }

    @ViewBuilder private var upNextList: some View {
        let videos = upNextQueue.isEmpty ? vm.relatedVideos : upNextQueue
        if videos.isEmpty {
            if vm.isLoading {
                ProgressView().padding(VFSpace.s32)
            } else {
                Text("Nothing up next.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .padding(VFSpace.s32)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: VFSpace.s8) {
                ForEach(Array(videos.enumerated()), id: \.offset) { _, item in
                    Button {
                        vm.load(video: item)
                    } label: {
                        UpNextRow(video: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct UpNextRow: View {
    let video: Video

    var body: some View {
        HStack(alignment: .top, spacing: VFSpace.s8) {
            ThumbnailFillView(primaryURL: video.thumbnailURL)
                .frame(width: 120, height: 120 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(video.title)
                    .font(.callout)
                    .lineLimit(2)
                if !video.channelTitle.isEmpty {
                    Text(video.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: VFTarget.pointer)
        .contentShape(Rectangle())
    }
}
#endif
