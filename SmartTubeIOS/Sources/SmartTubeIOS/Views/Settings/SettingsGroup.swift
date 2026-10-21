import SmartTubeIOSCore
import SwiftUI

// MARK: - Settings groups
//
// The groups of the functional brief (§15–17), in its order. Regular-width iPad and tvOS show a category
// list beside the selected group. Compact iOS and the Mac main window keep one form; Mac Settings keeps panes.

enum SettingsGroup: String, CaseIterable {
    case account, playback, languages, thisDevice, appearance, sponsorBlock, parentalControls, about

    var title: LocalizedStringKey {
        switch self {
        case .account: "Account"
        case .playback: "Playback"
        case .languages: "Languages"
        case .thisDevice: "This Device"
        case .appearance: "Appearance"
        case .sponsorBlock: "SponsorBlock"
        case .parentalControls: "Parental Controls"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .account: AppSymbol.personCircle
        case .playback: AppSymbol.play
        case .languages: AppSymbol.languages
        case .thisDevice: AppSymbol.clock
        case .appearance: AppSymbol.appearance
        case .sponsorBlock: AppSymbol.sponsorBlock
        case .parentalControls: AppSymbol.lock
        case .about: AppSymbol.questionCircle
        }
    }
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
        #elseif os(tvOS)
        categoryColumns
        #elseif os(iOS)
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad, horizontalSizeClass == .regular,
                VFColumn.supportsColumns(width: contentWidth, typeSize: typeSize)
            {
                categoryColumns
            } else {
                singleForm
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
        #else
        singleForm
        #endif
    }

    /// Every group in one scrolling form.
    private var singleForm: some View {
        let form = Form {
            ForEach(SettingsGroup.allCases, id: \.self) { sections($0) }
        }
        .accessibilityIdentifier(AccessibilityID.settingsForm)
        #if os(macOS)
        return form.formStyle(.grouped)
        #else
        return form
        #endif
    }

    private var categoryColumns: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: VFSpace.s8) {
                    Text("Settings", bundle: .module)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, VFSpace.s16)
                        .padding(.top, VFSpace.s16)
                    categoryList
                }
                .frame(width: VFColumn.listWidth(in: geometry.size.width, maximum: categoryColumnMaximum))
                Divider()
                categoryDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(tvOS)
        .padding(.horizontal, VFSpace.s32)
        .defaultFocus($focusedGroup, selectedGroup)
        .onChange(of: focusedGroup) { _, group in
            if let group { selectedGroup = group }
        }
        #endif
    }

    private var categoryColumnMaximum: CGFloat {
        #if os(tvOS)
        VFColumn.settingsCategoriesTVMaximum
        #else
        VFColumn.settingsCategoriesMaximum
        #endif
    }

    private var categoryList: some View {
        List(
            selection: Binding<SettingsGroup?>(
                get: { selectedGroup }, set: { if let group = $0 { selectedGroup = group } })
        ) {
            ForEach(SettingsGroup.allCases, id: \.self) { group in
                categoryButton(group)
                    .tag(group)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.settingsCategories)
        #if os(tvOS)
        .environment(\.defaultMinListRowHeight, VFTarget.tv)
        .focusSection()
        #endif
    }

    private func categoryButton(_ group: SettingsGroup) -> some View {
        let button = Button {
            selectedGroup = group
        } label: {
            HStack(spacing: VFSpace.s12) {
                Label {
                    Text(group.title, bundle: .module)
                } icon: {
                    Image(systemName: group.symbol)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: categoryTarget)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(AccessibilityID.settingsCategory(group.rawValue))
        .accessibilityAddTraits(selectedGroup == group ? [.isSelected] : [])
        #if os(tvOS)
        // Right enters the adjacent form using the system focus engine.
        return button.focused($focusedGroup, equals: group)
        #else
        return button.buttonStyle(.plain)
        #endif
    }

    private var categoryTarget: CGFloat {
        #if os(tvOS)
        VFTarget.tv
        #else
        VFTarget.touch
        #endif
    }

    private var categoryDetail: some View {
        let form = Form { sections(selectedGroup) }
            .id(selectedGroup)
            .accessibilityIdentifier(AccessibilityID.settingsForm)
        #if os(tvOS)
        return
            form
            .environment(\.defaultMinListRowHeight, VFTarget.tv)
            .focusSection()
            // Only the detail handles Back. From the category list the shell keeps its normal Back action.
            .onExitCommand { focusedGroup = selectedGroup }
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
            downloadsSection
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
            title: "SponsorBlock", symbol: AppSymbol.sponsorBlock, groups: [.sponsorBlock], height: 620,
            pushesDetail: true),
        SettingsPane(title: "Parental Controls", symbol: AppSymbol.lock, groups: [.parentalControls], height: 240),
        SettingsPane(title: "Account", symbol: AppSymbol.personCircle, groups: [.account, .about], height: 440),
    ]

    var settingsPanes: some View {
        TabView {
            ForEach(Self.panes) { pane in
                Tab {
                    paneForm(pane)
                        .frame(width: Self.paneWidth, height: pane.height)
                } label: {
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
