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

struct PINKeypadView: View {
    let title: String
    var subtitle: String?
    var errorMessage: String?
    /// Fired once exactly `pinLength` digits have been entered. The caller is
    /// responsible for calling `clear()` (via the returned reset) if the PIN was wrong.
    let onSubmit: (String) -> Void

    private let pinLength = 4

    @State private var digits: [Int] = []

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
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
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AccessibilityID.pinKeypadErrorMessage)
                }
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                ForEach(0..<pinLength, id: \.self) { index in
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 1.5)
                        .background(Circle().fill(index < digits.count ? Color.primary : .clear))
                        .frame(width: 16, height: 16)
                }
            }
            .accessibilityIdentifier(AccessibilityID.pinKeypadDots)

            keypad
        }
        .padding()
        .onChange(of: errorMessage) { _, newValue in
            if newValue != nil { digits.removeAll() }
        }
    }

    private var keypad: some View {
        let rows: [[Int?]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [nil, 0, -1],  // -1 == delete
        ]
        return VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 16) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        keyButton(for: rows[rowIndex][colIndex])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(for value: Int?) -> some View {
        switch value {
        case nil:
            Color.clear.frame(width: 64, height: 64)
        case -1:
            Button {
                guard !digits.isEmpty else { return }
                digits.removeLast()
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 64, height: 64)
            }
            .accessibilityIdentifier(AccessibilityID.pinKeypadDelete)
        case .some(let digit):
            Button {
                appendDigit(digit)
            } label: {
                Text("\(digit)")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.secondary.opacity(0.15)))
            }
            .accessibilityIdentifier(AccessibilityID.pinKeypadDigit(digit))
        }
    }

    private func appendDigit(_ digit: Int) {
        guard digits.count < pinLength else { return }
        digits.append(digit)
        if digits.count == pinLength {
            let pin = digits.map(String.init).joined()
            onSubmit(pin)
        }
    }
}
