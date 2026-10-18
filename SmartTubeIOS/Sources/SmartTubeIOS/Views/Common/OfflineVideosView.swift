import SmartTubeIOSCore
import SwiftUI

struct OfflineWatchButton: View {
    let video: Video
    let action: () -> Void
    private var isQueued: Bool {
        OfflineCoordinator.shared.snapshot.jobs.contains {
            $0.videoID == video.id && [.queued, .resolving, .downloading].contains($0.state)
        }
    }
    var body: some View {
        Button(action: action) {
            Label {
                isQueued ? Text("Offline watch · queued", bundle: .module) : Text("Offline watch", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.download)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineWatch)
        .disabled(video.isLive || video.isUpcoming || video.isDownloaded)
    }
}

/// Minimum target of the icon-only row buttons (cancel, delete) on each input model; tvOS keeps its focus effect.
#if os(iOS)
private let offlineIconTarget = VFTarget.touch
#elseif os(macOS)
private let offlineIconTarget = VFTarget.pointer
#else
private let offlineIconTarget = VFTarget.tv
#endif

struct OfflineVideosView: View {
    @State private var coordinator = OfflineCoordinator.shared
    @State private var showsProgress = false
    @State private var showsDeleteAll = false
    @State private var deletion: Deletion?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One job or one video; the confirmation names the track or the video.
    private enum Deletion {
        case job(OfflineJob)
        case video(id: String, title: String)
    }

    private var snapshot: OfflineSnapshot { coordinator.snapshot }
    private var isRemoving: Bool { !(snapshot.pendingRemovals ?? []).isEmpty }
    /// Read when a control renders and again when a confirmation is tapped: a dialog may already be open in another
    /// window when a removal starts.
    private var isLocked: Bool {
        OfflinePresentation.isLocked(
            storageError: coordinator.error, persistenceBlocked: coordinator.persistenceBlocked,
            pendingRemovals: snapshot.pendingRemovals)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $showsProgress) {
                Text("Library", bundle: .module).tag(false)
                Text("Downloads", bundle: .module).tag(true)
            } label: {
                Text("Offline videos", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, VFSpace.s8)
            .accessibilityIdentifier(AccessibilityID.offlinePagePicker)
            let state = OfflinePresentation.pageState(
                ready: coordinator.ready, error: coordinator.error,
                isEmpty: showsProgress ? snapshot.jobs.isEmpty : snapshot.entries.isEmpty)
            switch state {
            case .loading:
                ProgressView { Text("Loading offline videos…", bundle: .module) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .storageError(let message):
                storageError(message)
            case .empty:
                if showsProgress { emptyDownloads } else { emptyLibrary }
            case .content:
                if showsProgress { jobList } else { libraryList }
            }
        }
        .navigationTitle(Text("Offline videos", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showsDeleteAll = true
                } label: {
                    Label {
                        Text("Delete all offline videos", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.trash)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.offlineDeleteAll)
                .disabled(!coordinator.ready || isLocked)
                .confirmationDialog(
                    Text("Delete all offline videos?", bundle: .module), isPresented: $showsDeleteAll,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        guard coordinator.ready, !isLocked else { return }
                        coordinator.remove(videoID: nil)
                    } label: {
                        Text("Delete all", bundle: .module)
                    }
                    .disabled(!coordinator.ready || isLocked)
                    Button(role: .cancel) {
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                } message: {
                    Text(
                        "This cancels all offline downloads and deletes every saved video, audio track, translation and their cache. Watch history, your Google account and settings stay as they are. This cannot be undone.",
                        bundle: .module)
                }
            }
        }
        .task { coordinator.start() }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible, presenting: deletion
        ) { item in
            Button(role: .destructive) {
                defer { deletion = nil }
                guard !isLocked else { return }
                switch item {
                case .job(let job): coordinator.remove(videoID: job.videoID, jobID: job.id)
                case .video(let id, _): coordinator.remove(videoID: id)
                }
            } label: {
                Text("Delete", bundle: .module)
            }
            .disabled(isLocked)
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: { item in
            switch item {
            case .job:
                Text("This removes the task and its downloaded files. Other saved tracks are kept.", bundle: .module)
            case .video:
                Text(
                    "This removes the video, all downloaded audio and translations, and its pending downloads.",
                    bundle: .module)
            }
        }
    }

    private var deletionTitle: Text {
        switch deletion {
        case .job(let job): Text("Delete “\(job.track.label)”?", bundle: .module)
        case .video(_, let title): Text("Delete “\(title)”?", bundle: .module)
        case nil: Text(verbatim: "")  // verbatim: the dialog is hidden without a deletion
        }
    }

    // MARK: States

    private func storageError(_ message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text("Offline library is unavailable", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.warning)
            }
        } description: {
            Text(message)
        } actions: {
            Button {
                coordinator.retryStorage()
            } label: {
                Text("Try Again", bundle: .module)
            }
            .buttonStyle(.vfProminent)
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label {
                Text("No offline videos", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.download)
            }
        } description: {
            Text(
                "Choose Offline watch from a video's menu. Accepted downloads continue when you leave this page.",
                bundle: .module)
        }
    }

    private var emptyDownloads: some View {
        ContentUnavailableView {
            Label {
                Text("No downloads", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.download)
            }
        } description: {
            Text("Downloads you start with Offline watch appear here until you delete them.", bundle: .module)
        }
    }

    /// Storage failure above saved content, and the pending removal that holds every other change.
    @ViewBuilder private var notices: some View {
        if let error = coordinator.error { OfflineStorageNotice(message: error) }
        if isRemoving {
            Section {
                HStack(spacing: VFSpace.s12) {
                    ProgressView()
                    Text("Deleting… Other offline actions wait until it finishes.", bundle: .module)
                }
            }
        }
    }

    // MARK: Library

    private var libraryList: some View {
        List {
            notices
            ForEach(snapshot.entries) { entry in
                let title = OfflinePresentation.title(of: entry.id, in: snapshot.entries)
                HStack(spacing: VFSpace.s8) {
                    NavigationLink {
                        OfflineVideoDetail(videoID: entry.id)
                    } label: {
                        OfflineEntryLabel(
                            entry: entry, title: title,
                            status: OfflinePresentation.entryStatus(entry, jobs: snapshot.jobs))
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineEntry(entry.id))
                    Button(role: .destructive) {
                        deletion = .video(id: entry.id, title: title)
                    } label: {
                        Label {
                            Text("Delete video and files", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.trash)
                        }
                        .frame(minWidth: offlineIconTarget, minHeight: offlineIconTarget)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(isLocked)
                    .accessibilityIdentifier(AccessibilityID.offlineDeleteEntry(entry.id))
                }
            }
        }
    }

    // MARK: Downloads

    private var jobList: some View {
        List {
            notices
            if OfflinePresentation.showsYieldNotice(isYielding: coordinator.isYielding, jobs: snapshot.jobs) {
                Section {
                    Label {
                        Text("Downloads wait while a video starts or buffers. This is not an error.", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.pause)
                    }
                }
            }
            ForEach(OfflinePresentation.groups(jobs: snapshot.jobs, entries: snapshot.entries)) { group in
                Section {
                    ForEach(group.jobs) { job in jobRow(job, title: group.title) }
                } header: {
                    Text(group.title)
                }
                .headerProminence(.increased)
            }
        }
        .buttonStyle(.borderless)
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
            : AnyLayout(HStackLayout(spacing: VFSpace.s12))
    }

    private func jobRow(_ job: OfflineJob, title: String) -> some View {
        let status = OfflinePresentation.status(job)
        let part = OfflinePresentation.part(of: job.track)
        return rowLayout {
            Image(systemName: part.symbol)
                .foregroundStyle(.secondary)
                .frame(minWidth: VFSpace.s24)
                .accessibilityLabel(part.title)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(job.track.label)
                status.label
                if case .downloading(let progress) = status {
                    // The status text carries the percentage for VoiceOver.
                    ProgressView(value: progress).accessibilityHidden(true)
                }
                if let error = job.error {
                    Text(OfflinePresentation.failureText(error))
                        .font(.footnote)
                        .foregroundStyle(VFColor.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: VFSpace.s8) {
                jobAction(job)
                Button(role: .destructive) {
                    deletion = .job(job)
                } label: {
                    Label {
                        Text("Delete task and files", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.trash)
                    }
                    .frame(minWidth: offlineIconTarget, minHeight: offlineIconTarget)
                }
                .labelStyle(.iconOnly)
                .disabled(isLocked)
                .accessibilityIdentifier(AccessibilityID.offlineDeleteJob(job.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(AccessibilityID.offlineJob(job.id))
    }

    @ViewBuilder private func jobAction(_ job: OfflineJob) -> some View {
        switch OfflinePresentation.action(job) {
        case .cancel:
            Button {
                guard !isLocked else { return }
                coordinator.cancel(job)
            } label: {
                Label {
                    Text("Cancel download", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.xmarkCircle)
                }
                .frame(minWidth: offlineIconTarget, minHeight: offlineIconTarget)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .disabled(isLocked)
            .accessibilityIdentifier(AccessibilityID.offlineCancel(job.id))
        case .retry:
            Button {
                guard !isLocked else { return }
                coordinator.retry(job)
            } label: {
                Text("Retry", bundle: .module)
            }
            .buttonStyle(.bordered)
            .disabled(isLocked)
            .accessibilityIdentifier(AccessibilityID.offlineRetry(job.id))
        case .open:
            NavigationLink {
                OfflineVideoDetail(videoID: job.videoID)
            } label: {
                Text("Open", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Rows and status

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

private struct OfflineEntryLabel: View {
    let entry: OfflineEntry
    let title: String
    let status: OfflinePresentation.EntryStatus
    @Environment(\.dynamicTypeSize) private var typeSize

    #if os(tvOS)
    private static let thumbnailWidth: CGFloat = 240
    #else
    private static let thumbnailWidth: CGFloat = 112
    #endif

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VFSpace.s12))
        let parts = OfflinePresentation.parts(entry)
        layout {
            OfflineCover(url: entry.video.thumbnailURL, width: Self.thumbnailWidth)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(title).font(.headline)
                if !entry.video.channelTitle.isEmpty {
                    Text(entry.video.channelTitle).font(.footnote).foregroundStyle(.secondary)
                }
                status.label
                if !parts.isEmpty {
                    Text(parts.map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Symbol and text; the colour is never the only signal.
private struct OfflineStatusLabel: View {
    let text: Text
    let symbol: String
    let style: AnyShapeStyle

    var body: some View {
        // Not a Label: in a List row it takes the wide list icon column and wraps the text.
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.s4) {
            Image(systemName: symbol).accessibilityHidden(true)
            text
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(style)
    }
}

extension OfflinePresentation.JobStatus {
    fileprivate var label: OfflineStatusLabel {
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
    fileprivate var title: String {
        switch self {
        case .video: String(localized: "Video", bundle: .module)
        case .audio: String(localized: "Audio", bundle: .module)
        case .translation: String(localized: "Translation", bundle: .module)
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .video: AppSymbol.film
        case .audio: AppSymbol.audioTrack
        case .translation: AppSymbol.translation
        }
    }
}
