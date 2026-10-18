import SmartTubeIOSCore
import SwiftUI

// MARK: - PINKeypadView (#126)
//
// Reusable 4-digit PIN entry: dot progress indicator + on-screen numeric keypad.
// Used both by SettingsPINLockView (verifying an existing PIN to unlock Settings) and
// ParentalControlsSheet (setting/changing/removing the PIN) — built as on-screen buttons
// rather than a TextField/keyboard so behavior is identical on iOS, macOS and tvOS
// (a tvOS on-screen keyboard for a numeric PIN is a poor, slow experience with the
// focus engine; this reads exactly like every other tvOS/iOS PIN pad).
// iPhone and iPad draw a 3 × 4 pad of round keys; tvOS draws one row (1–9, 0, delete) that the
// remote walks left and right with the system focus.

struct PINKeypadView: View {
    let title: String
    var subtitle: String?
    var errorMessage: String?
    /// Fired once exactly `pinLength` digits have been entered. The pad then empties itself, so a
    /// wrong PIN can be retyped at once; the caller sets `errorMessage` through `rejection(_:)`.
    let onSubmit: (String) -> Void

    private let pinLength = 4
    #if os(tvOS)
    private let keySize = VFTarget.tv
    private let dotSize: CGFloat = 28
    #else
    /// The preferred key side; it grows with the text size (see `keySide(fitting:)` for the limits).
    @ScaledMetric(relativeTo: .title) private var keySize: CGFloat = 78
    private let dotSize: CGFloat = 14
    #endif
    private let rowSpacing = VFSpace.s16
    private let keySpacing = VFSpace.s24

    @State private var digits: [Int] = []

    /// Shows `message` and speaks it. Called for every rejected PIN, so a repeated mistake, whose text
    /// does not change, is announced again, as is an error that arrives with a new step of the flow.
    static func rejection(_ message: String) -> String {
        AccessibilityNotification.Announcement(message).post()
        return message
    }

    var body: some View {
        #if os(iOS)
        // Four rows of keys do not fit a landscape iPhone or the largest text sizes: the pad then scrolls.
        GeometryReader { proxy in
            ScrollView {
                pad(keySide: keySide(fitting: proxy.size.width))
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        #else
        // A plain stack: the macOS Settings window sizes itself to its content, and tvOS has a single row of keys.
        pad(keySide: keySize)
        #endif
    }

    #if os(iOS)
    /// Three keys and their gaps stay inside `width` (the pad's padding is at most `keySpacing` a side),
    /// and a key is never smaller than the touch target.
    private func keySide(fitting width: CGFloat) -> CGFloat {
        let fitting = (width - 4 * keySpacing) / 3
        return max(VFTarget.touch, min(keySize, fitting))
    }
    #endif

    private func pad(keySide: CGFloat) -> some View {
        VStack(spacing: VFSpace.s24) {
            VStack(spacing: VFSpace.s8) {
                Text(title)
                    .font(.title2.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(VFColor.danger)
                        .accessibilityIdentifier(AccessibilityID.pinKeypadErrorMessage)
                }
            }
            .multilineTextAlignment(.center)

            HStack(spacing: dotSize * 1.25) {
                ForEach(0..<pinLength, id: \.self) { index in
                    Circle()
                        .strokeBorder(.primary, lineWidth: 1.5)
                        .background(Circle().fill(index < digits.count ? Color.primary : .clear))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            // The full PIN is never shown or spoken: only how many digits are in.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(digits.count) of \(pinLength) digits entered", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.pinKeypadDots)

            keypad(keySide: keySide)
        }
        .padding()
        // A container, so a caller's identifier (e.g. `parentalControls.enterNew`) does not replace the keys' own.
        .accessibilityElement(children: .contain)
    }

    private func keypad(keySide: CGFloat) -> some View {
        #if os(tvOS)
        HStack(spacing: VFSpace.s16) {
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0, -1], id: \.self) { keyButton(for: $0, side: keySide) }
        }
        .focusSection()
        #else
        let rows: [[Int?]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [nil, 0, -1],  // -1 == delete
        ]
        return VStack(spacing: rowSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: keySpacing) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        keyButton(for: rows[rowIndex][colIndex], side: keySide)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func keyButton(for value: Int?, side: CGFloat) -> some View {
        switch value {
        case nil:
            Color.clear.frame(width: side, height: side)
        case -1:
            Button {
                guard !digits.isEmpty else { return }
                digits.removeLast()
            } label: {
                Image(systemName: AppSymbol.deleteBackward)
                    .font(.title2)
                    .frame(width: side, height: side)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Delete Digit", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.pinKeypadDelete)
        case .some(let digit):
            Button {
                appendDigit(digit)
            } label: {
                digitLabel(digit, side: side)
            }
            .accessibilityIdentifier(AccessibilityID.pinKeypadDigit(digit))
        }
    }

    private func digitLabel(_ digit: Int, side: CGFloat) -> some View {
        #if os(tvOS)
        // tvOS draws its own focus platter around the button.
        Text("\(digit)")
            .font(.title2)
            .frame(width: side, height: side)
        #else
        Text("\(digit)")
            .font(.title)
            .frame(width: side, height: side)
            .background(Circle().fill(.secondary.opacity(0.15)))
            .contentShape(Circle())
        #endif
    }

    private func appendDigit(_ digit: Int) {
        guard digits.count < pinLength else { return }
        digits.append(digit)
        if digits.count == pinLength {
            let pin = digits.map(String.init).joined()
            digits.removeAll()
            onSubmit(pin)
        }
    }
}
