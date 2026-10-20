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
    let isSelected: Bool
    let status: OfflinePresentation.EntryStatus
    let tracks: [OfflinePresentation.TrackBadge]
    @Environment(\.dynamicTypeSize) private var typeSize

    #if os(tvOS)
    private static let thumbnailWidth: CGFloat = 240
    #else
    private static let thumbnailWidth: CGFloat = 104
    #endif

    var body: some View {
        // Accessibility sizes stack the cover above full, untruncated text.
        let compact = !typeSize.isAccessibilitySize
        let layout =
            compact
            ? AnyLayout(HStackLayout(alignment: .top, spacing: VFSpace.s12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
        return VStack(alignment: .leading, spacing: VFSpace.s8) {
            layout {
                OfflineCover(url: entry.video.thumbnailURL, width: Self.thumbnailWidth)
                VStack(alignment: .leading, spacing: VFSpace.s4) {
                    Text(title).font(.headline).lineLimit(compact ? 3 : nil)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    if !entry.video.channelTitle.isEmpty {
                        Text(entry.video.channelTitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            status.label
            OfflineBadgeLayout {
                ForEach(tracks) { item in
                    OfflineTrackBadge(item: item)
                        .accessibilityIdentifier(AccessibilityID.offlineTrackBadge(entry.id, item.id))
                }
            }
        }
        .padding(.vertical, VFSpace.s8)
        .multilineTextAlignment(.leading)
    }
}

private struct OfflineTrackBadge: View {
    let item: OfflinePresentation.TrackBadge

    var body: some View {
        HStack(spacing: VFSpace.s4) {
            Image(systemName: OfflinePresentation.part(of: item.track).symbol)
            Text(item.compactLabel.isEmpty ? item.label : item.compactLabel)
                .lineLimit(1)
            switch item.status {
            case .downloading, .resolving:
                ProgressView().controlSize(.small)
            case .completed:
                EmptyView()
            default:
                Image(systemName: item.status.label.symbol)
                    .foregroundStyle(item.status.label.style)
            }
        }
        .font(.caption)
        .frame(minHeight: VFSpace.s20)
        .padding(.horizontal, VFSpace.s8)
        .padding(.vertical, VFSpace.s4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: VFRadius.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("offline.statusLine \(Text(item.label)) \(item.status.label.text)", bundle: .module))
    }
}

/// Wrap whole chips, keeping each label on one line.
private struct OfflineBadgeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            let frame = result.frames[index]
            view.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + VFSpace.s4
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + VFSpace.s4
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}

struct OfflineTransferSummary: View {
    let jobs: [OfflineJob]
    let action: () -> Void

    var body: some View {
        let summary = OfflinePresentation.transferSummary(jobs)
        if summary.isVisible {
            Button(action: action) {
                VStack(alignment: .leading, spacing: VFSpace.s8) {
                    HStack(spacing: VFSpace.s12) {
                        Label {
                            Text("Downloads", bundle: .module).font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: AppSymbol.download).foregroundStyle(.tint)
                        }
                        Spacer()
                        if let progress = summary.progress {
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        Image(systemName: AppSymbol.chevronRight)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: VFSpace.s4) {
                        if summary.activeCount > 0 {
                            Text(summary.countText).foregroundStyle(.secondary)
                        }
                        if summary.failures > 0 {
                            Text("Failed downloads: \(summary.failures)", bundle: .module)
                                .foregroundStyle(VFColor.danger)
                        }
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    if let progress = summary.progress { ProgressView(value: progress) }
                }
                .padding(.horizontal, VFSpace.s16)
                .padding(.vertical, VFSpace.s12)
                .frame(maxWidth: VFColumn.readableMaximum)
                .background(VFColor.elevated, in: RoundedRectangle(cornerRadius: VFRadius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: VFRadius.card).strokeBorder(.quaternary)
                }
                .shadow(color: .black.opacity(0.12), radius: VFSpace.s8, y: VFSpace.s4)
                .contentShape(RoundedRectangle(cornerRadius: VFRadius.card))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.offlineTransferSummary)
            .padding(.horizontal, VFSpace.s16)
            .padding(.vertical, VFSpace.s12)
        }
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

extension OfflineStatusLabel {
    func detail(_ text: String?) -> Self {
        var copy = self
        copy.detail = text
        return copy
    }
}

/// Total size of the saved offline files, for the toolbar. Hidden until something is saved.
struct OfflineTotalsLabel: View {
    let entries: [OfflineEntry]
    let jobs: [OfflineJob]
    let sizes: OfflineDiskSizes

    var body: some View {
        let saved = OfflineSizes.totals(entries: entries, jobs: jobs, sizes: sizes).onDisk
        if saved > 0 {
            let text = OfflinePresentation.bytesText(saved)
            Text(text)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(Text("Offline storage used: \(text)", bundle: .module))
                .accessibilityIdentifier(AccessibilityID.offlineTotals)
        }
    }
}

extension View {
    /// Keeps `sizes` current: measured again whenever the library changes, and once a second while a download runs.
    func offlineSizes(
        _ sizes: Binding<OfflineDiskSizes>, store: OfflineLibraryStore, snapshot: OfflineSnapshot
    )
        -> some View
    {
        modifier(
            OfflineSizesModifier(
                sizes: sizes, store: store, revision: snapshot.revision,
                isActive: snapshot.jobs.contains(where: OfflineSizes.isActive)))
    }
}

private struct OfflineSizesModifier: ViewModifier {
    private struct Trigger: Hashable {
        let revision: UInt64
        let isActive: Bool
    }
    @Binding var sizes: OfflineDiskSizes
    let revision: UInt64
    let isActive: Bool
    @State private var scanner: OfflineSizeScanner

    init(sizes: Binding<OfflineDiskSizes>, store: OfflineLibraryStore, revision: UInt64, isActive: Bool) {
        _sizes = sizes
        _scanner = State(initialValue: OfflineSizeScanner(store: store))
        self.revision = revision
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        content.task(id: Trigger(revision: revision, isActive: isActive)) {
            while !Task.isCancelled {
                if let read = try? await scanner.sizes(), !Task.isCancelled, read != sizes { sizes = read }
                guard isActive else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
