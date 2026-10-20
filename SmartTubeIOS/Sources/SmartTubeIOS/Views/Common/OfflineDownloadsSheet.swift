import SmartTubeIOSCore
import SwiftUI

#if os(iOS)
private let offlineIconTarget = VFTarget.touch
#elseif os(macOS)
private let offlineIconTarget = VFTarget.pointer
#else
private let offlineIconTarget = VFTarget.tv
#endif

/// All file tasks, optionally scoped to a video, with newest tasks first.
struct OfflineDownloadsSheet: View {
    let videoID: String?
    @State private var filter: OfflinePresentation.DownloadFilter
    @State private var coordinator = OfflineCoordinator.shared
    @State private var sizes = OfflineDiskSizes()
    @State private var deletion: OfflineJob?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(videoID: String? = nil, filter: OfflinePresentation.DownloadFilter = .all) {
        self.videoID = videoID
        _filter = State(initialValue: filter)
    }

    private var snapshot: OfflineSnapshot { coordinator.snapshot }
    private var jobs: [OfflineJob] {
        OfflinePresentation.downloadJobs(snapshot.jobs, videoID: videoID, filter: filter)
    }
    private var isLocked: Bool {
        OfflinePresentation.isLocked(
            storageError: coordinator.error, persistenceBlocked: coordinator.persistenceBlocked,
            pendingRemovals: snapshot.pendingRemovals)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker(selection: $filter) {
                    ForEach(OfflinePresentation.DownloadFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                } label: {
                    Text("Downloads", bundle: .module)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityID.offlineDownloadsFilter)
                if let error = coordinator.error { OfflineStorageNotice(message: error) }
                if !(snapshot.pendingRemovals ?? []).isEmpty {
                    Label {
                        Text("Deleting… Other offline actions wait until it finishes.", bundle: .module)
                    } icon: {
                        ProgressView()
                    }
                }
                if OfflinePresentation.showsYieldNotice(isYielding: coordinator.isYielding, jobs: jobs) {
                    Label {
                        Text("Downloads wait while a video starts or buffers. This is not an error.", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.pause)
                    }
                }
                if jobs.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No downloads", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.download)
                        }
                    }
                }
                ForEach(jobs) { job in
                    jobRow(job, title: OfflinePresentation.title(of: job.videoID, in: snapshot.entries))
                }
            }
            .accessibilityIdentifier(AccessibilityID.offlineJobsList)
            .navigationTitle(Text("Downloads", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineDownloadsClose)
                }
            }
            .confirmationDialog(
                Text("Delete “\(deletion?.track.label ?? "")”?", bundle: .module),
                isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                titleVisibility: .visible, presenting: deletion
            ) { job in
                Button(role: .destructive) {
                    defer { deletion = nil }
                    guard !isLocked else { return }
                    coordinator.remove(videoID: job.videoID, jobID: job.id)
                } label: {
                    Text("Delete", bundle: .module)
                }
                .disabled(isLocked)
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { _ in
                Text("This removes the task and its downloaded files. Other saved tracks are kept.", bundle: .module)
            }
        }
        .offlineSizes($sizes, store: coordinator.store, snapshot: snapshot)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 640, minHeight: 400, idealHeight: 600)
        #endif
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private func jobRow(_ job: OfflineJob, title: String) -> some View {
        let status = OfflinePresentation.status(job)
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
            : AnyLayout(HStackLayout(spacing: VFSpace.s12))
        return layout {
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(title).font(.headline).lineLimit(2)
                Label {
                    Text(OfflinePresentation.TrackBadge(track: job.track, status: status).label)
                } icon: {
                    Image(systemName: OfflinePresentation.part(of: job.track).symbol)
                }
                status.label.detail(OfflinePresentation.jobSizeText(job, sizes: sizes))
                if case .downloading(let progress) = status {
                    ProgressView(value: progress).accessibilityHidden(true)
                }
                if let error = job.error {
                    Text(OfflinePresentation.failureText(error))
                        .font(.footnote).foregroundStyle(VFColor.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: VFSpace.s8) {
                jobAction(job)
                Button(role: .destructive) {
                    deletion = job
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
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(AccessibilityID.offlineJob(job.id))
        .offlineDeleteActions(
            Text("Delete task and files", bundle: .module), isDisabled: isLocked,
            identifier: AccessibilityID.offlineDeleteJob(job.id)
        ) { deletion = job }
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
        case .none:
            EmptyView()
        }
    }
}
