import SmartTubeIOSCore
import SwiftUI

struct OfflineWatchButton: View {
    let video: Video
    let action: () -> Void
    static func isQueued(_ video: Video) -> Bool {
        OfflineCoordinator.shared.snapshot.jobs.contains {
            $0.videoID == video.id && [.queued, .resolving, .downloading].contains($0.state)
        }
    }
    private var isQueued: Bool { Self.isQueued(video) }
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

/// Minimum target of the icon-only row buttons on each input model: cancel everywhere, delete on tvOS only (other
/// platforms delete by swipe or context menu). tvOS keeps its focus effect.
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
    @State private var assetSizes = OfflineDiskSizes()
    @State private var showsDeleteAll = false
    @State private var showsSponsorResult = false
    @State private var deletion: Deletion?
    @State private var selectedVideoID: String?
    /// Set once a video has filled the detail column; from then on only the person's choice is kept.
    @State private var hasShownVideo = false
    /// Video pushed from a completed download in a single column.
    @State private var openedVideoID: String?
    @State private var contentWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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

    private var showsColumns: Bool {
        #if os(macOS)
        VFColumn.supportsColumns(width: contentWidth, typeSize: typeSize, listMinimum: VFColumn.offlineListMinimum)
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
            && VFColumn.supportsColumns(
                width: contentWidth, typeSize: typeSize, listMinimum: VFColumn.offlineListMinimum)
        #else
        false
        #endif
    }

    var body: some View {
        adaptiveContent
            .navigationTitle(Text("Offline videos", bundle: .module))
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
            .onAppear(perform: syncSelection)
            .onChange(of: snapshot.entries.map(\.id)) { _, _ in syncSelection() }
            .onChange(of: showsColumns) { _, _ in syncSelection() }
            .onChange(of: selectedVideoID) { _, videoID in
                if videoID != nil { hasShownVideo = true }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    OfflineTotalsLabel(entries: snapshot.entries, jobs: snapshot.jobs, sizes: assetSizes)
                }
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
            .toolbar { ToolbarItem(placement: sponsorPlacement) { updateSponsorBlockButton } }
            .alert(
                Text("SponsorBlock updated", bundle: .module), isPresented: $showsSponsorResult,
                actions: {}, message: { Text(sponsorResultText) }
            )
            .task { coordinator.start() }
            .offlineSizes($assetSizes, store: coordinator.store, snapshot: snapshot)
            .navigationDestination(item: $openedVideoID) { OfflineVideoDetail(videoID: $0) }
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
                    Text(
                        "This removes the task and its downloaded files. Other saved tracks are kept.", bundle: .module)
                case .video:
                    Text(
                        "This removes the video, all downloaded audio and translations, and its pending downloads.",
                        bundle: .module)
                }
            }
    }

    private func syncSelection() {
        selectedVideoID = OfflinePresentation.columnSelection(
            selectedVideoID, entries: snapshot.entries, showsColumns: showsColumns, hasShownVideo: hasShownVideo)
    }

    @ViewBuilder private var adaptiveContent: some View {
        if showsColumns {
            GeometryReader { geometry in
                let listWidth = VFColumn.listWidth(
                    in: geometry.size.width, minimum: VFColumn.offlineListMinimum,
                    fraction: VFColumn.offlineListFraction, maximum: VFColumn.offlineListMaximum)
                HStack(spacing: 0) {
                    #if os(iOS)
                    // Plain rows: the grouped inset would take another 40 pt from a narrow column.
                    libraryPane.listStyle(.plain).frame(width: listWidth)
                    #else
                    libraryPane.frame(width: listWidth)
                    #endif
                    Divider()
                    Group {
                        if let videoID = OfflinePresentation.retainedSelection(
                            selectedVideoID, entries: snapshot.entries)
                        {
                            OfflineVideoDetail(videoID: videoID, isEmbedded: true).id(videoID)
                        } else {
                            ContentUnavailableView {
                                Label {
                                    Text("Select an offline video", bundle: .module)
                                } icon: {
                                    Image(systemName: AppSymbol.download)
                                }
                            } description: {
                                Text("Choose a video from the library to see its saved files.", bundle: .module)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            libraryPane
        }
    }

    private var libraryPane: some View {
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
        List(selection: showsColumns ? $selectedVideoID : nil) {
            notices
            ForEach(snapshot.entries) { entry in
                let title = OfflinePresentation.title(of: entry.id, in: snapshot.entries)
                let entryLabel = OfflineEntryLabel(
                    entry: entry, title: title, status: OfflinePresentation.entryStatus(entry, jobs: snapshot.jobs))
                Group {
                    if showsColumns {
                        Button {
                            selectedVideoID = entry.id
                        } label: {
                            entryLabel.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(selectedVideoID == entry.id ? [.isSelected] : [])
                        .accessibilityIdentifier(AccessibilityID.offlineEntry(entry.id))
                    } else {
                        NavigationLink {
                            OfflineVideoDetail(videoID: entry.id)
                        } label: {
                            entryLabel
                        }
                        .accessibilityIdentifier(AccessibilityID.offlineEntry(entry.id))
                    }
                }
                .offlineDeleteActions(
                    Text("Delete video and files", bundle: .module), isDisabled: isLocked,
                    identifier: AccessibilityID.offlineDeleteEntry(entry.id)
                ) {
                    deletion = .video(id: entry.id, title: title)
                }
                .tag(entry.id)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineLibraryList)
        #if os(macOS)
        .onDeleteCommand {
            guard showsColumns, !isLocked,
                let videoID = OfflinePresentation.retainedSelection(selectedVideoID, entries: snapshot.entries)
            else { return }
            deletion = .video(id: videoID, title: OfflinePresentation.title(of: videoID, in: snapshot.entries))
        }
        #endif
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
                    OfflineGroupHeader(
                        title: group.title,
                        sizes: OfflinePresentation.videoSizeText(
                            group.videoID, entries: snapshot.entries, sizes: assetSizes))
                }
                .headerProminence(.increased)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineJobsList)
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
            : AnyLayout(HStackLayout(spacing: VFSpace.s12))
    }

    private func jobRow(_ job: OfflineJob, title: String) -> some View {
        let status = OfflinePresentation.status(job)
        let part = OfflinePresentation.part(of: job.track)
        let row = rowLayout {
            Image(systemName: part.symbol)
                .foregroundStyle(.secondary)
                .frame(minWidth: VFSpace.s24)
                .accessibilityLabel(part.title)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(job.track.label)
                status.label.detail(OfflinePresentation.jobSizeText(job, sizes: assetSizes))
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
                #if os(tvOS)
                jobAction(job)
                // No swipe on tvOS, and the row itself takes no focus for a context menu.
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
                #else
                // The `.contain` row is no VoiceOver element of its own, so its main control carries the delete.
                jobAction(job).accessibilityAction(named: Text("Delete task and files", bundle: .module)) {
                    guard !isLocked else { return }
                    deletion = .job(job)
                }
                #endif
            }
            // Borderless on the row's own controls only: on the whole List it also reaches the swipe buttons,
            // and the trailing swipe then reveals nothing.
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(AccessibilityID.offlineJob(job.id))
        #if os(tvOS)
        return row
        #else
        return row.offlineDeleteActions(
            Text("Delete task and files", bundle: .module), isDisabled: isLocked,
            identifier: AccessibilityID.offlineDeleteJob(job.id)
        ) {
            deletion = .job(job)
        }
        #endif
    }

}

extension OfflineVideosView {
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
            // A Button, not a NavigationLink: a link inside the row turns the whole List cell into a push row,
            // and a swipe on it then opens the video instead of revealing Delete.
            Button {
                if showsColumns { selectedVideoID = job.videoID } else { openedVideoID = job.videoID }
            } label: {
                Text("Open", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Empty states

extension OfflineVideosView {
    var sponsorPlacement: ToolbarItemPlacement {
        #if os(tvOS)
        .primaryAction
        #else
        .secondaryAction
        #endif
    }

    fileprivate var emptyLibrary: some View {
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

    fileprivate var emptyDownloads: some View {
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
}

extension OfflineVideosView {
    var sponsorResultText: String {
        guard case .finished(let updated, let failed) = coordinator.sponsor.update else { return "" }
        return String(localized: "Updated \(updated) videos, failed \(failed).", bundle: .module)
    }

    var updateSponsorBlockButton: some View {
        let running = if case .running = coordinator.sponsor.update { true } else { false }
        return Button {
            Task {
                await coordinator.refreshAllSponsorSegments()
                showsSponsorResult = true
            }
        } label: {
            Label {
                if case .running(let done, let total) = coordinator.sponsor.update {
                    Text("Updating SponsorBlock \(done)/\(total)", bundle: .module)
                } else {
                    Text("Update SponsorBlock", bundle: .module)
                }
            } icon: {
                Image(systemName: AppSymbol.updateSponsorBlock)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineUpdateSponsorBlockAll)
        .disabled(
            !coordinator.ready || isLocked || running || !coordinator.sponsor.isEnabled()
                || snapshot.entries.allSatisfy { $0.assets.isEmpty })
    }
}
