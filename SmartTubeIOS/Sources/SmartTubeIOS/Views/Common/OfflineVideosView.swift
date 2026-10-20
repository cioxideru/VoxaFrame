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

struct OfflineVideosView: View {
    @State private var coordinator = OfflineCoordinator.shared
    @State private var downloads: OfflinePresentation.DownloadFilter?
    @State private var assetSizes = OfflineDiskSizes()
    @State private var showsDeleteAll = false
    @State private var showsSponsorResult = false
    @State private var deletion: OfflineEntry?
    @State private var selectedVideoID: String?
    /// Set once a video has filled the detail column; from then on only the person's choice is kept.
    @State private var hasShownVideo = false
    @State private var contentWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.innerTubeAPI) private var api
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PlayerRouter.self) private var router
    #else
    @State private var playbackVideo: Video?
    #endif

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
            .clipped()
            .safeAreaInset(edge: .top, spacing: 0) {
                OfflineTransferSummary(jobs: snapshot.jobs) {
                    downloads = .active
                }
            }
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
                    Button {
                        downloads = .all
                    } label: {
                        Label {
                            Text("Downloads", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.download)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineDownloads)
                }
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
            .sheet(item: $downloads) { filter in OfflineDownloadsSheet(filter: filter) }
            #if os(macOS)
        .navigationDestination(item: $playbackVideo) { video in PlayerView(video: video, api: api) }
            #elseif os(tvOS)
        .sheet(item: $playbackVideo) { video in PlayerView(video: video, api: api) }
            #endif
            .confirmationDialog(
                Text("Delete “\(deletion?.video.title ?? "")”?", bundle: .module),
                isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                titleVisibility: .visible, presenting: deletion
            ) { item in
                Button(role: .destructive) {
                    defer { deletion = nil }
                    guard !isLocked else { return }
                    coordinator.remove(videoID: item.id)
                } label: {
                    Text("Delete", bundle: .module)
                }
                .disabled(isLocked)
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { _ in
                Text(
                    "This removes the video, all downloaded audio and translations, and its pending downloads.",
                    bundle: .module)
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
            let state = OfflinePresentation.pageState(
                ready: coordinator.ready, error: coordinator.error,
                isEmpty: snapshot.entries.isEmpty)
            switch state {
            case .loading:
                ProgressView { Text("Loading offline videos…", bundle: .module) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .storageError(let message):
                storageError(message)
            case .empty:
                emptyLibrary
            case .content:
                libraryList
            }
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
                    entry: entry, title: title, status: OfflinePresentation.entryStatus(entry, jobs: snapshot.jobs),
                    tracks: OfflinePresentation.trackBadges(entry, jobs: snapshot.jobs))
                VStack(alignment: .leading, spacing: VFSpace.s4) {
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
                    OfflinePlaybackControls(entry: entry) { video in
                        #if os(iOS)
                        router.open(video: video, api: api)
                        #else
                        playbackVideo = video
                        #endif
                    }
                }
                .offlineDeleteActions(
                    Text("Delete video and files", bundle: .module), isDisabled: isLocked,
                    identifier: AccessibilityID.offlineDeleteEntry(entry.id)
                ) {
                    deletion = entry
                }
                .tag(entry.id)
                .listRowBackground(showsColumns && selectedVideoID == entry.id ? VFColor.surface : nil)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineLibraryList)
        #if os(macOS)
        .onDeleteCommand {
            guard showsColumns, !isLocked,
                let videoID = OfflinePresentation.retainedSelection(selectedVideoID, entries: snapshot.entries)
            else { return }
            deletion = snapshot.entries.first { $0.id == videoID }
        }
        #endif
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
