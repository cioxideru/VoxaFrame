import SmartTubeIOSCore
import SwiftUI

/// Ids of the videos that can be played offline: one cheap lookup for cards and the player, held by each coordinator.
/// Assigned only when it changes, so views reading it re-render when a video is saved or removed, not on every
/// progress tick.
@MainActor @Observable
final class OfflineSavedIDs {
    private(set) var ids: Set<String> = []
    func update(_ entries: [OfflineEntry]) {
        let next = OfflinePresentation.savedVideoIDs(entries)
        guard next != ids else { return }
        ids = next
    }
}

/// Reports whether a video is saved offline to `onChange`, and nothing else: it is the only view that reads the set,
/// so a card re-renders when its own state flips, not on every change to the set.
struct OfflineSavedObserver: View {
    let videoID: String
    let onChange: (Bool) -> Void

    var body: some View {
        let saved = OfflineCoordinator.shared.savedIDs.ids.contains(videoID)
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: saved, initial: true) { _, value in onChange(value) }
    }
}

/// A player title with the saved mark after it. VoiceOver hears one element: the title, then the saved status.
struct OfflineSavedTitle: View {
    let title: String
    let videoID: String
    var spacing: CGFloat = VFSpace.s4
    var identifier: String = ""

    var body: some View {
        let saved = OfflineCoordinator.shared.savedIDs.ids.contains(videoID)
        HStack(spacing: spacing) {
            Text(title)
                .accessibilityLabel(
                    saved ? Text("\(title), \(String(localized: "Saved offline", bundle: .module))") : Text(title)
                )
                .accessibilityIdentifier(identifier)
            if saved { OfflineSavedMark() }
        }
    }
}

/// The decorative "saved offline" mark; the status is spoken with the title.
struct OfflineSavedMark: View {
    var body: some View {
        Image(systemName: AppSymbol.offlineSaved)
            .font(.footnote.weight(.semibold))
            .accessibilityHidden(true)
    }
}

/// The player title with the mark after it.
struct PlayerTitleRow: View {
    let title: String
    let videoID: String
    var spacing: CGFloat = VFSpace.s4

    var body: some View {
        OfflineSavedTitle(
            title: title, videoID: videoID, spacing: spacing, identifier: AccessibilityID.playerTitleLabel
        )
        .font(.headline)
        .lineLimit(1)
        .foregroundStyle(VFColor.onMedia)
    }
}
