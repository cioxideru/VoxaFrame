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
}

/// View menu additions. AppKit supplies Enter/Exit Full Screen and its standard Control-Command-F command.
public struct MacWindowCommands: Commands {
    @FocusedBinding(\.playerInspectorVisible) private var inspectorVisible
    @FocusedValue(\.searchFiltersAction) private var searchFiltersAction

    public init() {}

    public var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(after: .sidebar) {
            Button(playerInspectorToggleTitle(isVisible: inspectorVisible == true)) {
                inspectorVisible?.toggle()
            }
            .disabled(inspectorVisible == nil)
            Button {
                searchFiltersAction?()
            } label: {
                Text("Show Search Filters…", bundle: .module)
            }
            .disabled(searchFiltersAction == nil)
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
