#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Mac scenes
//
// Used by AppEntry's macOS branch. Kept in the package so the native macOS compile of the package covers them.

private struct SearchFiltersActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var searchFiltersAction: (() -> Void)? {
        get { self[SearchFiltersActionKey.self] }
        set { self[SearchFiltersActionKey.self] = newValue }
    }
    /// The focused video surface (MacPlayerInteraction): the Playback menu acts on it.
    @Entry var macPlayback: MacPlaybackTarget?
    /// The window's sidebar (MainSidebarView): ⌘1… select its rows.
    @Entry var macSidebarNavigation: MacSidebarNavigation?
    /// The Offline videos screen's toolbar actions.
    @Entry var macOfflineActions: MacOfflineActions?
}

struct MacPlaybackTarget {
    let vm: PlaybackViewModel
    let seekBackSeconds: Double
    let seekForwardSeconds: Double
}

struct MacSidebarNavigation {
    let items: [ShellItem]
    let select: (ShellItem) -> Void
}

struct MacOfflineActions {
    let showDownloads: () -> Void
    /// Nil while deleting is unavailable (not ready, or a removal is running).
    let deleteAll: (() -> Void)?
}

/// Menu bar additions: View (inspector, search filters, ⌘1… sections), Playback and File (offline videos).
/// AppKit supplies Enter/Exit Full Screen and its standard Control-Command-F command.
public struct MacWindowCommands: Commands {
    @FocusedBinding(\.playerInspectorVisible) private var inspectorVisible
    @FocusedValue(\.searchFiltersAction) private var searchFiltersAction
    @FocusedValue(\.macPlayback) private var playback
    @FocusedValue(\.macSidebarNavigation) private var navigation
    @FocusedValue(\.macOfflineActions) private var offline

    public init() {}

    public var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(after: .sidebar) {
            Button(playerInspectorToggleTitle(isVisible: inspectorVisible == true)) {
                inspectorVisible?.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(inspectorVisible == nil)
            Button {
                searchFiltersAction?()
            } label: {
                Text("Show Search Filters…", bundle: .module)
            }
            .disabled(searchFiltersAction == nil)
            if let navigation {
                Divider()
                ForEach(Array(navigation.items.prefix(9).enumerated()), id: \.element) { index, item in
                    Button {
                        navigation.select(item)
                    } label: {
                        item.title
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
        // Applies to the focused video only, so Space and ⌘-arrows keep working in text fields.
        CommandMenu(Text("Playback", bundle: .module)) {
            Button {
                playback?.vm.togglePlayPause()
            } label: {
                playback?.vm.isPlaying == true ? Text("Pause", bundle: .module) : Text("Play", bundle: .module)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(playback == nil)
            Divider()
            Button {
                if let playback { playback.vm.seekRelative(seconds: -playback.seekBackSeconds) }
            } label: {
                Text("Skip Back", bundle: .module)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(playback == nil)
            Button {
                if let playback { playback.vm.seekRelative(seconds: playback.seekForwardSeconds) }
            } label: {
                Text("Skip Forward", bundle: .module)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(playback == nil)
            Divider()
            Button {
                playback?.vm.playPrevious()
            } label: {
                Text("Previous Video", bundle: .module)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(playback?.vm.hasPrevious != true)
            Button {
                playback?.vm.playNext()
            } label: {
                Text("Next Video", bundle: .module)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(playback?.vm.hasNext != true)
        }
        CommandGroup(after: .saveItem) {
            Button {
                offline?.showDownloads()
            } label: {
                Text("Downloads", bundle: .module)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(offline == nil)
            Button {
                offline?.deleteAll?()
            } label: {
                Text("Delete All Offline Videos…", bundle: .module)
            }
            .disabled(offline?.deleteAll == nil)
        }
    }
}

/// The separate Settings window (Command-comma).
public struct MacSettingsScene: Scene {
    let authService: AuthService
    let browseViewModel: BrowseViewModel
    let settingsStore: SettingsStore

    public init(authService: AuthService, browseViewModel: BrowseViewModel, settingsStore: SettingsStore) {
        self.authService = authService
        self.browseViewModel = browseViewModel
        self.settingsStore = settingsStore
    }

    public var body: some Scene {
        Settings {
            // The standard toolbar tabs; the panes with pushed links carry their own stack.
            SettingsView(showsPanes: true)
                // Inside the SettingsStore injection below: the scope reads the store from its ancestors.
                .vfGlassScope()
                .environment(authService)
                .environment(browseViewModel)
                .environment(settingsStore)
                .tint(settingsStore.settings.accentColor.color)
                .frame(minWidth: 480)
        }
    }
}
#endif
