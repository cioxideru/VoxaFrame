import SmartTubeIOSCore
import SwiftUI

// Rows, covers and status labels of the offline library, downloads and saved-video pages.

/// List section shown above content while the library cannot be read or saved:
/// the localized title, the reason exactly as reported, and a retry.
struct OfflineStorageNotice: View {
    let message: String

    var body: some View {
        Section {
            Label {
                Text(message)
            } icon: {
                Image(systemName: AppSymbol.warning)
            }
            .foregroundStyle(VFColor.danger)
            Button {
                OfflineCoordinator.shared.retryStorage()
            } label: {
                Text("Try Again", bundle: .module)
            }
        } header: {
            Text("Offline library is unavailable", bundle: .module)
        }
    }
}

/// Video cover from the network. Without a URL (a deep link carries none) a still placeholder, not a spinner;
/// offline the load fails to the same kind of placeholder, as covers are not cached (OQ-0019).
struct OfflineCover: View {
    let url: URL?
    let width: CGFloat

    var body: some View {
        Group {
            if let url {
                ThumbnailFillView(primaryURL: url)
            } else {
                VFColor.surface.overlay {
                    Image(systemName: AppSymbol.film).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct OfflineEntryLabel: View {
    let entry: OfflineEntry
    let title: String
    let status: OfflinePresentation.EntryStatus
    @Environment(\.dynamicTypeSize) private var typeSize

    #if os(tvOS)
    private static let thumbnailWidth: CGFloat = 240
    #else
    /// I-Offline: leaves about 220 pt of text beside the cover in the iPad portrait column.
    private static let thumbnailWidth: CGFloat = 104
    #endif

    var body: some View {
        // Accessibility sizes stack the cover above full, untruncated text.
        let compact = !typeSize.isAccessibilitySize
        let layout =
            compact
            ? AnyLayout(HStackLayout(alignment: .top, spacing: VFSpace.s12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
        let parts = OfflinePresentation.parts(entry)
        var statusLine = status.label
        statusLine.detail = parts.isEmpty ? nil : parts.map(\.title).formatted(.list(type: .and, width: .narrow))
        return layout {
            OfflineCover(url: entry.video.thumbnailURL, width: Self.thumbnailWidth)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(title).font(.headline).lineLimit(compact ? 3 : nil)
                if !entry.video.channelTitle.isEmpty {
                    Text(entry.video.channelTitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                statusLine.lineLimit(compact ? 1 : nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A Button label centres multi-line text by default.
        .multilineTextAlignment(.leading)
    }
}

extension View {
    /// Row deletion without an inline button: trailing swipe and a context menu, both opening the caller's
    /// confirmation. tvOS has no swipe; its context menu opens with a long press on the focused row.
    func offlineDeleteActions(
        _ title: Text, isDisabled: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        modifier(OfflineDeleteActions(title: title, isDisabled: isDisabled, identifier: identifier, action: action))
    }
}

private struct OfflineDeleteActions: ViewModifier {
    let title: Text
    let isDisabled: Bool
    let identifier: String
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.contextMenu { button(role: .destructive) }
        #else
        // No destructive role on the swipe button: it would animate the row away before the confirmation.
        content
            .contextMenu { button(role: .destructive) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { button(role: nil).tint(VFColor.destructiveFill) }
        #endif
    }

    private func button(role: ButtonRole?) -> some View {
        Button(role: role, action: action) {
            Label {
                title
            } icon: {
                Image(systemName: AppSymbol.trash)
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }
}

/// Symbol and text; the colour is never the only signal.
struct OfflineStatusLabel: View {
    let text: Text
    let symbol: String
    let style: AnyShapeStyle
    /// Secondary text after the status on the same line, e.g. the saved parts.
    var detail: String?

    var body: some View {
        // Not a Label: in a List row it takes the wide list icon column and wraps the text.
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.s4) {
            Image(systemName: symbol).accessibilityHidden(true)
            if let detail {
                let detailText = Text(verbatim: detail)  // verbatim: localized by the caller
                    .fontWeight(.regular).foregroundStyle(.secondary)
                // One Text, so the line wraps as a sentence rather than as two columns.
                Text(
                    "offline.statusLine \(text) \(detailText)", bundle: .module,
                    comment: "Offline library row: the video's status, then the saved parts (e.g. Video, Audio)")
            } else {
                text
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(style)
    }
}

extension OfflinePresentation.JobStatus {
    var label: OfflineStatusLabel {
        switch self {
        case .queued:
            OfflineStatusLabel(
                text: Text("Queued", bundle: .module), symbol: AppSymbol.clock, style: AnyShapeStyle(.secondary))
        case .waitingForTranslation:
            OfflineStatusLabel(
                text: Text("Waiting for translation", bundle: .module), symbol: AppSymbol.hourglass,
                style: AnyShapeStyle(.secondary))
        case .resolving:
            OfflineStatusLabel(
                text: Text("Preparing", bundle: .module), symbol: AppSymbol.hourglass,
                style: AnyShapeStyle(.secondary))
        case .downloading(let progress):
            OfflineStatusLabel(
                text: Text(
                    "Downloading · \(progress, format: .percent.precision(.fractionLength(0)))", bundle: .module),
                symbol: AppSymbol.download, style: AnyShapeStyle(.primary))
        case .completed:
            OfflineStatusLabel(
                text: Text("Completed", bundle: .module), symbol: AppSymbol.checkmarkCircle,
                style: AnyShapeStyle(VFColor.success))
        case .failed:
            OfflineStatusLabel(
                text: Text("Failed", bundle: .module), symbol: AppSymbol.warning, style: AnyShapeStyle(VFColor.danger))
        case .cancelled:
            OfflineStatusLabel(
                text: Text("Cancelled", bundle: .module), symbol: AppSymbol.xmarkCircle,
                style: AnyShapeStyle(.secondary))
        }
    }
}

extension OfflinePresentation.EntryStatus {
    fileprivate var label: OfflineStatusLabel {
        switch self {
        case .downloading(let progress):
            OfflinePresentation.JobStatus.downloading(progress).label
        case .preparing:
            OfflinePresentation.JobStatus.resolving.label
        case .queued:
            OfflinePresentation.JobStatus.queued.label
        case .failed:
            OfflineStatusLabel(
                text: Text("A download failed", bundle: .module), symbol: AppSymbol.warning,
                style: AnyShapeStyle(VFColor.danger))
        case .ready:
            OfflineStatusLabel(
                text: Text("Ready to watch", bundle: .module), symbol: AppSymbol.checkmarkCircle,
                style: AnyShapeStyle(VFColor.success))
        case .notReady:
            OfflineStatusLabel(
                text: Text("Video not saved yet", bundle: .module), symbol: AppSymbol.film,
                style: AnyShapeStyle(.secondary))
        }
    }
}

extension OfflinePresentation.Part {
    var title: String {
        switch self {
        case .video: String(localized: "Video", bundle: .module)
        case .audio: String(localized: "Audio", bundle: .module)
        case .translation: String(localized: "Translation", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .video: AppSymbol.film
        case .audio: AppSymbol.audioTrack
        case .translation: AppSymbol.translation
        }
    }
}
