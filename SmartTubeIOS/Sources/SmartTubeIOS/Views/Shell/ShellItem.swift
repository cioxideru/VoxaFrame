import SmartTubeIOSCore
import SwiftUI

// MARK: - ShellItem
//
// A root destination of the iPad and Mac sidebars: one of the five sections, or the Queue (PLAN-0027 A1).
// The Queue has no `AppSection` case, so the section raw values, tab identifiers and the tvOS/iPhone tab
// bars stay as they are; iPhone, compact iPad windows and tvOS reach the queue through Library › Queue.

enum ShellItem: Hashable, Identifiable {
    case section(AppSection)
    case queue

    /// Also the UI-test identifier: `AccessibilityID.tab(id)`.
    var id: String {
        switch self {
        case .section(let section): section.rawValue
        case .queue: "Queue"
        }
    }

    var title: Text {
        switch self {
        case .section(let section): Text(verbatim: section.rawValue)  // verbatim: raw value, as the tab bars (OQ-0019)
        case .queue: Text("Queue", bundle: .module)
        }
    }

    var icon: String {
        switch self {
        case .section(let section): section.icon
        case .queue: AppSymbol.queue
        }
    }

    @MainActor @ViewBuilder
    func destination(api: InnerTubeAPI) -> some View {
        switch self {
        case .section(let section):
            section.destination(api: api)
        case .queue:
            PlaylistView(
                playlistId: CurrentQueueStore.playlistID, playlistTitle: String(localized: "Queue", bundle: .module),
                api: api)
        }
    }
}
