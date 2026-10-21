import SmartTubeIOSCore
import SwiftUI

// MARK: - SectionsSettingsView

/// Lets the user configure which sections appear in the sidebar / tab bar.
/// Mirrors Android's `MainUIData` section ordering/enabling UI.
struct SectionsSettingsView: View {
    @Environment(SettingsStore.self) private var store

    private let allSections = BrowseSection.allSections

    /// #156: visible sections in the user's own order (drag-to-reorder below), each
    /// resolved back to its `BrowseSection` for a title/icon.
    private var visibleSections: [BrowseSection] {
        store.settings.enabledSections.compactMap { type in allSections.first { $0.type == type } }
    }

    private var hiddenSections: [BrowseSection] {
        allSections.filter { !store.settings.enabledSections.contains($0.type) }
    }

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                ForEach(visibleSections) { section in
                    HStack {
                        Text(section.title)
                        Spacer()
                        Button {
                            // Don't allow disabling the last section.
                            guard store.settings.enabledSections.count > 1 else { return }
                            store.settings.enabledSections.removeAll { $0 == section.type }
                        } label: {
                            Image(systemName: AppSymbol.removeCircle)
                                .foregroundStyle(.red)
                                .frame(minWidth: VFTarget.touch, minHeight: VFTarget.touch)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Hide \(section.title)", bundle: .module))
                        .disabled(store.settings.enabledSections.count <= 1)
                    }
                }
                .onMove { offsets, destination in
                    store.settings.enabledSections.move(fromOffsets: offsets, toOffset: destination)
                }
            } header: {
                Text("Visible — drag to reorder")
            }

            if !hiddenSections.isEmpty {
                Section("Hidden") {
                    ForEach(hiddenSections) { section in
                        Button {
                            // Append to the end of the user's current order, rather than
                            // recomputing from canonical order, so re-enabling a section
                            // doesn't discard any reordering already done above.
                            store.settings.enabledSections.append(section.type)
                        } label: {
                            HStack {
                                Text(section.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: AppSymbol.addCircle).foregroundStyle(VFColor.success)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Show \(section.title)", bundle: .module))
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.settingsVisibleSectionsList)
        .navigationTitle("Visible Sections")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - SponsorBlockExcludedChannelsView

/// Lists channels excluded from SponsorBlock processing.
/// Saved exclusions can be removed here via swipe-to-delete.
struct SponsorBlockExcludedChannelsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let sortedChannels = store.settings.sponsorBlockExcludedChannels
            .sorted { $0.value.localizedCompare($1.value) == .orderedAscending }
        return List {
            if sortedChannels.isEmpty {
                ContentUnavailableView(
                    "No Excluded Channels",
                    systemImage: AppSymbol.personCircleMinus
                )
            } else {
                ForEach(sortedChannels, id: \.key) { _, title in
                    Text(title)
                }
                .onDelete { indices in
                    let ids = indices.map { sortedChannels[$0].key }
                    ids.forEach { store.settings.sponsorBlockExcludedChannels.removeValue(forKey: $0) }
                }
            }
        }
        .navigationTitle("Excluded Channels")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        #endif
    }
}

// MARK: - GitHubQRView (tvOS)

#if os(tvOS)
/// The About link on tvOS: a QR code to scan with a phone, since tvOS has no browser.
struct GitHubQRView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Opaque and appearance-aware, so the primary and secondary labels keep their contrast in Light and Dark.
            VFColor.surface.ignoresSafeArea()

            VStack(spacing: VFSpace.s32) {
                VStack(spacing: VFSpace.s12) {
                    Image(systemName: AppSymbol.sourceCode)
                        .font(.system(size: 56))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)

                    Text("VoxaFrame on GitHub")
                        .font(.largeTitle).fontWeight(.bold)

                    Text("Scan the QR code with your phone to view the project on GitHub.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                QRCodeView(content: url.absoluteString)
                    .frame(width: 280, height: 280)
                    .padding(VFSpace.s16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))

                Text(url.absoluteString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: AppSymbol.xmark)
                    .font(.headline)
            }
            .padding(40)
        }
    }
}
#endif
