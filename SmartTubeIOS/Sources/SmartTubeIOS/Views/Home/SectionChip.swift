#if !os(tvOS)
import SwiftUI

// MARK: - SectionChip
//
// VF/FilterChip, category variant: one selected chip per row (the Home sections; Search keeps its removable
// `FilterChip`). Selection shows as fill contrast plus the selected trait, never as a tint alone. The tvOS chip draws
// its own focus and stays in HomeView.

struct SectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    #if os(iOS)
    @Environment(SettingsStore.self) private var store
    #endif

    /// Capsule height from the design; on touch screens the button adds margin up to the 44 pt target.
    private static let height: CGFloat = 40
    private static let targetInset: CGFloat = {
        #if os(iOS)
        return (VFTarget.touch - height) / 2
        #else
        return 0
        #endif
    }()

    var body: some View {
        #if os(iOS)
        let selectedFill = AnyShapeStyle(store.settings.accentColor.color ?? VFColor.action)
        let selectedLabel = AnyShapeStyle(store.settings.accentColor.onColor)
        #else
        let selectedFill = AnyShapeStyle(.primary)
        let selectedLabel = AnyShapeStyle(.background)
        #endif
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? selectedLabel : AnyShapeStyle(.primary))
                .padding(.horizontal, VFSpace.s16)
                .frame(minHeight: Self.height)
                .background(isSelected ? selectedFill : AnyShapeStyle(VFColor.surface), in: Capsule())
                .overlay {
                    // Increase Contrast: unselected chips get an edge so they do not rely on a faint fill.
                    if contrast == .increased, !isSelected {
                        Capsule().strokeBorder(Color.primary, lineWidth: 1)
                    }
                }
                .padding(.vertical, Self.targetInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .vfAnimation(VFMotion.fast, value: isSelected)
    }
}
#endif
