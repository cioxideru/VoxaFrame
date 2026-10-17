#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Mac scenes
//
// Used by AppEntry's macOS branch. Kept in the package so the native macOS compile of the package covers them.

/// View menu for the main window: the standard sidebar and toolbar groups, plus Show/Hide Inspector. No custom shortcuts.
public struct MacWindowCommands: Commands {
    @FocusedBinding(\.playerInspectorVisible) private var inspectorVisible

    public init() {}

    public var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        // Not `InspectorCommands()`: that drives only the trailing inspector, while below 1000 pt the player shows
        // the same panel under the video. This item toggles the player's single visibility state in both layouts.
        CommandGroup(after: .sidebar) {
            Button(playerInspectorToggleTitle(isVisible: inspectorVisible == true)) {
                inspectorVisible?.toggle()
            }
            .disabled(inspectorVisible == nil)
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
            SettingsView()
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
