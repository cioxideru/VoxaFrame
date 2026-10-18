import SwiftUI

// MARK: - Settings groups
//
// The groups of the functional brief (§15–17), in its order. iPhone, iPad, tvOS and the macOS main window
// show them all in one scrolling form; the macOS Settings window (Command-comma) shows them as toolbar tabs.

enum SettingsGroup: CaseIterable {
    case account, playback, languages, thisDevice, appearance, sponsorBlock, parentalControls, about
}

extension SettingsView {
    @ViewBuilder
    var settingsContent: some View {
        #if os(macOS)
        if showsPanes {
            settingsPanes
        } else {
            singleForm
        }
        #else
        singleForm
        #endif
    }

    /// Every group in one scrolling form.
    private var singleForm: some View {
        let form = Form {
            ForEach(SettingsGroup.allCases, id: \.self) { sections($0) }
        }
        #if os(macOS)
        return form.formStyle(.grouped)
        #else
        return form
        #endif
    }

    @ViewBuilder
    private func sections(_ group: SettingsGroup) -> some View {
        switch group {
        case .account:
            accountSection
        case .playback:
            playerSection
            videoCodecsSection
        case .languages:
            SettingsLanguageSections()
        case .thisDevice:
            generalSection
            iCloudSection
        case .appearance:
            uiSection
            feedFiltersSection
            homeSectionsSection
        case .sponsorBlock:
            sponsorBlockSection
            deArrowSection
        case .parentalControls:
            parentalControlsSection
        case .about:
            aboutSection
        }
    }
}

#if os(macOS)
/// One toolbar tab of the macOS Settings window. The window takes the pane's size; a longer form scrolls.
private struct SettingsPane: Identifiable {
    let title: LocalizedStringKey
    let symbol: String
    let groups: [SettingsGroup]
    let height: CGFloat
    /// Visible Sections and Excluded Channels are pushed links, inert without a stack of their own.
    var pushesDetail = false

    var id: String { symbol }
}

extension SettingsView {
    private static let paneWidth: CGFloat = 520
    private static let panes: [SettingsPane] = [
        SettingsPane(title: "General", symbol: AppSymbol.settings, groups: [.playback, .thisDevice], height: 620),
        SettingsPane(title: "Languages", symbol: AppSymbol.languages, groups: [.languages], height: 460),
        SettingsPane(
            title: "Appearance", symbol: AppSymbol.appearance, groups: [.appearance], height: 600, pushesDetail: true),
        SettingsPane(
            title: "SponsorBlock", symbol: AppSymbol.skipForward, groups: [.sponsorBlock], height: 620,
            pushesDetail: true),
        SettingsPane(title: "Parental Controls", symbol: AppSymbol.lock, groups: [.parentalControls], height: 240),
        SettingsPane(title: "Account", symbol: AppSymbol.personCircle, groups: [.account, .about], height: 440),
    ]

    var settingsPanes: some View {
        TabView {
            ForEach(Self.panes) { pane in
                paneForm(pane)
                    .frame(width: Self.paneWidth, height: pane.height)
                    // tabItem, not Tab: Tab needs macOS 15 and the app still supports macOS 14.
                    .tabItem {
                        Label {
                            Text(pane.title, bundle: .module)
                        } icon: {
                            Image(systemName: pane.symbol)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func paneForm(_ pane: SettingsPane) -> some View {
        let form = Form {
            ForEach(pane.groups, id: \.self) { sections($0) }
        }
        .formStyle(.grouped)
        if pane.pushesDetail {
            NavigationStack { form }
        } else {
            form
        }
    }
}
#endif
