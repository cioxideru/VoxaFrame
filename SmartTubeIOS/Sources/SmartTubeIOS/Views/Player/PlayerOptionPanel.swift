import SmartTubeIOSCore
import SwiftUI

// MARK: - Player option panels (VF/PlaybackOptions in VF/Sheet)
//
// Quality, speed, audio and translation, captions and the sleep timer share one header and one row.
// The container is the platform's own: a sheet with detents on iPhone, a popover on iPad and Mac
// (`playerOptionPanel(isPresented:)`), and on tvOS a full-height menu over the dimmed video, drawn inside the
// player so the player's Back handling closes it first and focus returns to the player.
// Opening a panel never restarts playback or changes the queue.

/// Header (Cancel, title) above the panel's content. The caller puts the accessibility identifier on it.
struct PlayerOptionPanel<Content: View>: View {
    let title: Text
    @Binding var isPresented: Bool
    var cancelAccessibilityIdentifier: String = AccessibilityID.playerOptionPanelCancel
    @ViewBuilder var content: Content
    #if os(iOS)
    @State private var contentHeight: CGFloat?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            #if os(iOS)
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, height in
                    contentHeight = height > 0 ? height : nil
                }
                .frame(idealHeight: contentHeight, maxHeight: contentHeight)
            #else
            content
            #endif
        }
        .modifier(OptionPanelChrome())
        #if os(iOS)
        .accessibilityElement(children: .contain)
        #endif
    }

    private var titleView: some View {
        title
            .font(.headline)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    /// Cancel and the centred title. A hidden copy of Cancel on the other side keeps the title centred at every
    /// text size; when the three do not fit on one line (large Dynamic Type), Cancel goes above the title.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                cancelButton
                Spacer()
                titleView.fixedSize(horizontal: true, vertical: false)
                Spacer()
                cancelButton
                    .hidden()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                cancelButton
                titleView
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, VFSpace.s8)
            }
        }
    }

    @ViewBuilder private var cancelButton: some View {
        #if os(tvOS)
        Button {
            isPresented = false
        } label: {
            Text("Cancel", bundle: .module)
        }
        .accessibilityIdentifier(cancelAccessibilityIdentifier)
        .buttonStyle(PickerHeaderButtonStyle())
        .padding()
        #else
        // The target and hit area are inside the label, so the whole minimum-size area is the button.
        Button {
            isPresented = false
        } label: {
            Text("Cancel", bundle: .module)
                .frame(minWidth: playerActionTarget, minHeight: playerActionTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(cancelAccessibilityIdentifier)
        .padding(.horizontal)
        .padding(.vertical, VFSpace.s4)
        #endif
    }
}

/// One choice in an option panel: a checkmark and the selected trait, not only a tint (VF/PlaybackOptions).
struct PlayerOptionRow: View {
    let title: Text
    var detail: Text?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .foregroundStyle(.primary)
                    if let detail {
                        detail
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: VFSpace.s8)
                if isSelected {
                    Image(systemName: AppSymbol.checkmark)
                        .fontWeight(.semibold)
                        .foregroundStyle(checkmarkStyle)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(minHeight: playerActionTarget)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// iPhone and iPad: the accent, whose pairs are tested on the panel. On Mac and TV the system accent can be
    /// pale (Yellow, Mint), so the mark takes the label colour, as system menus do.
    private var checkmarkStyle: AnyShapeStyle {
        #if os(iOS)
        AnyShapeStyle(.tint)
        #else
        AnyShapeStyle(.primary)
        #endif
    }
}

/// The smallest player action: the touch target, or the 10-foot target on tvOS.
var playerActionTarget: CGFloat {
    #if os(tvOS)
    VFTarget.tv
    #else
    VFTarget.touch
    #endif
}

/// A short explanation under a panel's choices, such as which videos a setting affects.
struct PlayerOptionFootnote: View {
    let text: Text

    var body: some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, VFSpace.s8)
    }
}

#if os(tvOS)
/// Width of the tvOS option menu (T-Player-Menu).
private let tvPanelWidth: CGFloat = 720

/// tvOS: a full-height menu at the trailing edge over the dimmed video.
private struct OptionPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            content
                .frame(width: tvPanelWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VFRadius.panel, style: .continuous))
                .padding(.trailing, VFMargin.tvHorizontal)
                .padding(.vertical, VFMargin.tvVertical)
        }
        .ignoresSafeArea()
    }
}
#else
/// iOS and macOS: the system sheet or popover is the container; this only sizes a popover.
private struct OptionPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        // The measured scroll content supplies the height; the system can still shrink its viewport.
        content.frame(minWidth: 320, idealWidth: 360, alignment: .top)
        #else
        content.frame(minWidth: 320, idealWidth: 360, maxHeight: .infinity, alignment: .top)
        #endif
    }
}

/// The control a popover points at. Panels opened from the More menu, or whose own button is not shown, point
/// at the More button.
enum PlayerOptionPanelTrigger: Hashable {
    case speed, quality, audio, sleepTimer, more
}

/// Where each trigger is, collected from the controls overlay up to the view that presents the panels.
private struct PlayerOptionPanelTriggers: PreferenceKey {
    static var defaultValue: [PlayerOptionPanelTrigger: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [PlayerOptionPanelTrigger: Anchor<CGRect>],
        nextValue: () -> [PlayerOptionPanelTrigger: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

/// With neither the trigger nor a More button on screen, the popover points at the middle of the player.
private let optionPanelFallbackAnchor = UnitPoint(x: 0.5, y: 0.5)

extension View {
    /// Marks the control that opens a panel, so the panel's popover points at it.
    func playerOptionPanelTrigger(_ trigger: PlayerOptionPanelTrigger) -> some View {
        anchorPreference(key: PlayerOptionPanelTriggers.self, value: .bounds) { [trigger: $0] }
    }

    /// Presents an option panel pointing at `trigger`. iOS chooses an arrow edge that fits the window;
    /// `arrowEdge` preserves the existing macOS placement.
    func playerOptionPanel<Panel: View>(
        isPresented: Binding<Bool>, trigger: PlayerOptionPanelTrigger?, arrowEdge: Edge = .top,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        modifier(
            OptionPanelPresentation(
                isPresented: isPresented, trigger: trigger, arrowEdge: arrowEdge, onDismiss: onDismiss, panel: panel))
    }
}

/// A popover that points at the control that opened it. The player keeps its controls on screen while a panel
/// is open, so the trigger stays. On iPhone it adapts to a sheet with medium and large detents; in a vertically
/// compact (landscape) iPhone layout it stays a popover, so the video stays in view and a portrait-only sheet
/// never takes over the landscape player.
private struct OptionPanelPresentation<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let trigger: PlayerOptionPanelTrigger?
    let arrowEdge: Edge
    let onDismiss: (() -> Void)?
    let panel: () -> Panel
    @Environment(SettingsStore.self) private var store
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var sourceRect: CGRect?
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .backgroundPreferenceValue(PlayerOptionPanelTriggers.self) { triggers in
                let source = trigger.flatMap { triggers[$0] } ?? triggers[.more]
                Color.clear
                    .onGeometryChange(for: CGRect?.self) { proxy in
                        return source.map { proxy[$0] }.flatMap { $0.isEmpty ? nil : $0 }
                    } action: {
                        sourceRect = $0
                    }
                    .allowsHitTesting(false)
            }
            // Keep presentation on the player, not on a background created during anchor resolution.
            // A missing/rebuilt control uses the player centre without interrupting presentation.
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: sourceRect.map { .rect(.rect($0)) } ?? .point(optionPanelFallbackAnchor),
                arrowEdge: nil
            ) {
                panel()
                    .background {
                        if let onDismiss {
                            OptionPanelDismissalObserver {
                                if !isPresented { onDismiss() }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .tint(store.settings.accentColor.color)
                    .presentationCompactAdaptation(compactAdaptation)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        #else
        content.backgroundPreferenceValue(PlayerOptionPanelTriggers.self) { triggers in
            GeometryReader { proxy in
                let own = trigger.flatMap { triggers[$0] }
                let source = own ?? triggers[.more]
                let anchor: PopoverAttachmentAnchor =
                    source.map { .rect(.rect(proxy[$0])) } ?? .point(optionPanelFallbackAnchor)
                // Preserve the existing macOS arrow preference.
                let edge = own == nil && source != nil ? Edge.bottom : arrowEdge
                Color.clear.popover(isPresented: $isPresented, attachmentAnchor: anchor, arrowEdge: edge) {
                    panel()
                        // The player is hosted outside RootView, so the panel takes the app's accent itself.
                        .tint(store.settings.accentColor.color)
                        .presentationCompactAdaptation(compactAdaptation)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        #endif
    }

    private var compactAdaptation: PresentationAdaptation {
        #if os(iOS)
        horizontalSizeClass == .regular || verticalSizeClass == .compact ? .popover : .sheet
        #else
        .automatic
        #endif
    }
}
#endif
