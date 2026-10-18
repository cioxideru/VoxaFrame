import SmartTubeIOSCore
import SwiftUI

/// Shared controls with separate persisted choices for regular videos and Shorts: the same eight speeds
/// (`AppSettings.availableSpeeds`), stored in `playbackSpeed` or `shortsPlaybackSpeed`.
/// A grid of eight on iPhone and iPad (VF/PlaybackOptions speed); a list of rows on tvOS for the remote and on Mac.
struct PlayerSpeedPicker: View {
    let vm: PlaybackViewModel
    @Binding var showSpeedPicker: Bool
    @Environment(SettingsStore.self) private var store
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    #if os(tvOS)
    @Namespace private var speedPickerNamespace
    @FocusState private var speedPickerFocused: Bool
    #endif

    /// "1×", "1.25×" in the user's number format; also the Shorts speed button's value.
    static func label(for speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private var speedKey: WritableKeyPath<AppSettings, Double> {
        vm.isShortsPlayer ? \.shortsPlaybackSpeed : \.playbackSpeed
    }

    var body: some View {
        let panel = PlayerOptionPanel(title: Text("Playback Speed", bundle: .module), isPresented: $showSpeedPicker) {
            choicesScroll
        }
        .accessibilityIdentifier(AccessibilityID.playerSpeedPicker)
        #if os(tvOS)
        panel
            .focusScope(speedPickerNamespace)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                speedPickerFocused = true
            }
            .onExitCommand { showSpeedPicker = false }
        #else
        panel
        #endif
    }

    @ViewBuilder private var choicesScroll: some View {
        let scroll = ScrollView {
            VStack(spacing: 0) {
                speedChoices
                PlayerOptionFootnote(
                    text: vm.isShortsPlayer
                        ? Text("Shorts only. Regular videos keep their own speed.", bundle: .module)
                        : Text("Regular videos only. Shorts keep their own speed.", bundle: .module))
            }
        }
        #if os(tvOS)
        scroll
            .prefersDefaultFocus(in: speedPickerNamespace)
            .focused($speedPickerFocused)
        #else
        scroll
        #endif
    }

    private func isSelected(_ speed: Double) -> Bool {
        abs(store.settings[keyPath: speedKey] - speed) < 0.01
    }

    private func select(_ speed: Double) {
        store.settings[keyPath: speedKey] = speed
        vm.setPlaybackSpeed(speed)
        showSpeedPicker = false
    }

    /// TV, Mac, and iPhone or iPad at accessibility text sizes: a list of rows, where a speed never truncates. On the
    /// Mac the selection is the checkmark in the label colour, readable with any system accent (white on a pale
    /// accent such as Yellow or Mint would not be).
    private var speedRows: some View {
        VStack(spacing: 0) {
            ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                PlayerOptionRow(title: Text(Self.label(for: speed)), isSelected: isSelected(speed)) {
                    select(speed)
                }
                .accessibilityIdentifier(AccessibilityID.playerSpeed(speed))
                Divider()
            }
        }
    }

    #if !os(iOS)
    private var speedChoices: some View { speedRows }
    #else
    @ViewBuilder private var speedChoices: some View {
        if dynamicTypeSize.isAccessibilitySize {
            speedRows
        } else {
            speedGrid
        }
    }

    /// Four across, each speed on one line.
    private var speedGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: VFSpace.s8), count: 4)
        return LazyVGrid(columns: columns, spacing: VFSpace.s8) {
            ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                speedCell(speed, selected: isSelected(speed))
            }
        }
        .padding()
    }

    /// The selected speed is filled with the accent and carries a checkmark.
    private func speedCell(_ speed: Double, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous)
        return Button {
            select(speed)
        } label: {
            HStack(spacing: VFSpace.s4) {
                if selected {
                    Image(systemName: AppSymbol.checkmark)
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(Self.label(for: speed))
            }
            .font(.body.weight(.semibold))
            .lineLimit(1)
            // The design's tested label colour on each accent fill.
            .foregroundStyle(selected ? store.settings.accentColor.onColor : Color.primary)
            .frame(maxWidth: .infinity, minHeight: VFTarget.touch)
            .background(selected ? (store.settings.accentColor.color ?? .accentColor) : VFColor.surface, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.playerSpeed(speed))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    #endif
}
