#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

/// Tabs of the Mac player inspector.
enum PlayerInspectorTab: Hashable {
    case upNext, description, comments
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
                case .upNext: PlayerUpNextList(vm: vm) { vm.load(video: $0) }
                case .description: ScrollView { descriptionContent }
                case .comments:
                    // Never show another video's list while this one's request is pending.
                    let isCurrent = vm.comments.videoId == activeVideoID
                    ScrollView {
                        CommentsList(
                            comments: isCurrent ? vm.comments.comments : [],
                            isLoading: !isCurrent || vm.comments.isLoading
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Keyed by the playing video, so Next with Comments open loads the new video's comments.
        .onChange(of: inspectorTab == .comments ? activeVideoID : nil, initial: true) { _, videoID in
            if let videoID { vm.comments.load(videoId: videoID) }
        }
    }
}

#endif
