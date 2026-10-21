import SmartTubeIOSCore
import SwiftUI

struct OfflineDownloadSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: [OfflineTrack] = []
    @State private var videoID: String?
    @State private var audioID: String?
    @State private var translates = false
    @State private var language = "ru"
    @State private var error: String?
    @State private var loading = true
    @State private var reload = 0

    private var videos: [OfflineTrack] { OfflineSelection.videos(in: catalog) }
    private var selectedVideo: OfflineTrack? { videos.first { $0.id == videoID } }
    private var audio: [OfflineTrack] {
        selectedVideo.map { OfflineSelection.audio(for: $0, in: catalog) } ?? []
    }
    private var preferredLanguage: String? {
        OfflineSelection.defaultLanguage(preference: store.settings.preferredAudioLanguage)
    }
    private var preferredAudioID: String? {
        OfflineSelection.preferredAudio(in: audio, language: preferredLanguage)?.id
    }
    private var tracks: [OfflineTrack]? {
        guard let selectedVideo, let selectedAudio = audio.first(where: { $0.id == audioID }) else { return nil }
        return try? OfflineSelection.tracks(
            video: selectedVideo, audio: selectedAudio, translation: translates ? language : nil, catalog: catalog)
    }
    /// The library refuses new tasks while a removal is pending and ignores them while storage is blocked.
    private var isLocked: Bool {
        OfflinePresentation.isLocked(
            storageError: OfflineCoordinator.shared.error,
            persistenceBlocked: OfflineCoordinator.shared.persistenceBlocked,
            pendingRemovals: OfflineCoordinator.shared.snapshot.pendingRemovals)
    }
    @Environment(SettingsStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                // Read in the body so a storage failure re-renders the sheet and disables Download.
                if let storageError = OfflineCoordinator.shared.error {
                    OfflineStorageNotice(message: storageError)
                }
                Section {
                    header
                }
                Section {
                    if loading {
                        ProgressView { Text("Loading available streams…", bundle: .module) }
                    } else if let error {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: AppSymbol.warning)
                        }
                        .foregroundStyle(VFColor.danger)
                        Button {
                            reload += 1
                        } label: {
                            Text("Try Again", bundle: .module)
                        }
                    } else {
                        mediaSelections
                        if let tracks {
                            if let size = OfflineSelection.estimatedBytes(for: tracks) {
                                Text(
                                    "Estimated media size: \(OfflinePresentation.bytesText(size))",
                                    bundle: .module
                                )
                                .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: "YouTube")  // verbatim: provider brand
                } footer: {
                    VStack(alignment: .leading, spacing: VFSpace.s4) {
                        Text(
                            "Downloads only the selected video and audio. You can add other tracks later in Library.",
                            bundle: .module)
                        #if !os(iOS)
                        // OfflineSourceResolver offers HLS packages on iPhone and iPad only.
                        Text(
                            "On this device videos are saved as direct files. HLS packages are saved on iPhone and iPad.",
                            bundle: .module)
                        #endif
                    }
                }
                if !loading && error == nil {
                    Section {
                        translationSelections
                    } header: {
                        Text("Translation · Yandex", bundle: .module)
                    } footer: {
                        if translates {
                            Text("Translation size will be known after it is prepared.", bundle: .module)
                        }
                    }
                }
                #if !os(iOS)
                Section { downloadButton }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                #endif
            }
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                downloadButton.padding(VFSpace.s16).background(.regularMaterial)
            }
            #endif
            .navigationTitle(Text("Offline watch", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
            }
            #if !os(tvOS)
            .pickerStyle(.menu)
            #endif
        }
        // Presented from the player's UIKit-hosted cover too, which does not pass the root `.tint` on.
        .tint(store.settings.accentColor.color)
        .task(id: reload) {
            loading = true
            do {
                let loaded = try await OfflineCoordinator.shared.catalog(video: video)
                try Task.checkCancellation()
                catalog = loaded
                videoID = videos.first { $0.videoSize?.height == 720 && $0.codec == .h264 }?.id ?? videos.first?.id
                audioID = preferredAudioID
                if let preferredLanguage, YandexVOTClient.targetLanguages.contains(preferredLanguage) {
                    language = preferredLanguage
                    translates = true
                } else {
                    translates = false
                }
                error = videos.isEmpty ? OfflineLibraryError.unavailable.localizedDescription : nil
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
        .onChange(of: videoID) { _, _ in
            if !audio.contains(where: { $0.id == audioID }) { audioID = preferredAudioID }
        }
    }

    private var downloadButton: some View {
        Button {
            guard let tracks, !isLocked else { return }
            OfflineCoordinator.shared.enqueue(video: video, tracks: tracks)
            dismiss()
        } label: {
            Label {
                Text("Download", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.download)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.vfProminent)
        .disabled(loading || tracks == nil || isLocked)
        .accessibilityIdentifier(AccessibilityID.offlineSelectionDownload)
    }

    private var header: some View {
        HStack(spacing: VFSpace.s12) {
            OfflineCover(url: video.thumbnailURL, width: 80)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(video.title).font(.headline)
                if !video.channelTitle.isEmpty {
                    Text(video.channelTitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mediaSelections: some View {
        Group {
            Picker(selection: $videoID) {
                ForEach(videos) { track in
                    Text(track.videoChoiceLabel + (track.kind == .hls ? " · HLS" : " · MP4"))
                        .tag(Optional(track.id))
                }
            } label: {
                Text("Video stream", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.offlineSelectionVideo)
            Picker(selection: $audioID) {
                ForEach(audio) { track in
                    Text(track.audioLabel ?? track.label).tag(Optional(track.id))
                }
            } label: {
                Text("Audio Track", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.offlineSelectionAudio)
            .accessibilityValue(audio.first { $0.id == audioID }.map { $0.audioLabel ?? $0.label } ?? "")
            if audio.isEmpty {
                Text("No compatible audio track is available for this video stream.", bundle: .module)
            }
        }
    }

    private var translationSelections: some View {
        Group {
            Toggle(isOn: $translates) {
                Text("Yandex translation", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.offlineSelectionTranslate)
            if translates {
                Picker(selection: $language) {
                    ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                        Text(OfflinePresentation.languageName(language)).tag(language)
                    }
                } label: {
                    Text("Translation language", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.offlineSelectionLanguage)
                .accessibilityValue(OfflinePresentation.languageName(language))
            }
        }
    }
}
