#if os(iOS)
import SmartTubeIOSCore
import SwiftUI

struct PlayerLevelFeedback: Equatable {
    let level: PlayerPanGesture.Level
    let value: CGFloat?
}

struct PlayerLevelOverlay: View {
    let feedback: PlayerLevelFeedback?
    let showsHints: Bool

    var body: some View {
        if feedback != nil || showsHints {
            HStack(spacing: 0) {
                zone(.brightness)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
                zone(.volume)
            }
            .allowsHitTesting(false)
        }
    }

    private func zone(_ level: PlayerPanGesture.Level) -> some View {
        VStack {
            Spacer()
            if let feedback, feedback.level == level {
                VStack(spacing: 8) {
                    Label(title(level), systemImage: symbol(level))
                    if let value = feedback.value {
                        Text(Double(value), format: .percent.precision(.fractionLength(0)))
                            .font(.title2.monospacedDigit())
                        ProgressView(value: Double(value)).tint(.white).frame(width: 88)
                    } else {
                        Text("Unavailable")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(16)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(title(level)))
                .accessibilityValue(
                    feedback.value.map { Text(Double($0), format: .percent.precision(.fractionLength(0))) }
                        ?? Text("Unavailable")
                )
                .accessibilityIdentifier(
                    level == .brightness ? AccessibilityID.playerBrightnessGesture : AccessibilityID.playerVolumeGesture
                )
            } else if showsHints {
                Label(title(level), systemImage: symbol(level))
                    .font(.caption)
                    .opacity(0.65)
                    .accessibilityHidden(true)
                Image(systemName: AppSymbol.verticalAdjustment).font(.caption).opacity(0.65)
                    .accessibilityHidden(true)
            }
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(feedback?.level == level ? Color.white.opacity(0.04) : .clear)
    }

    private func title(_ level: PlayerPanGesture.Level) -> LocalizedStringKey {
        level == .brightness ? "Brightness" : "Volume"
    }

    private func symbol(_ level: PlayerPanGesture.Level) -> String {
        level == .brightness ? AppSymbol.brightness : AppSymbol.speaker
    }
}
#endif
