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
    private var preferredAudioID: String? { audio.first { $0.isOriginalAudio == true }?.id ?? audio.first?.id }
    private var tracks: [OfflineTrack]? {
        guard let selectedVideo, let selectedAudio = audio.first(where: { $0.id == audioID }) else { return nil }
        return try? OfflineSelection.tracks(
            video: selectedVideo, audio: selectedAudio, translation: translates ? language : nil, catalog: catalog)
    }
    var body: some View {
        VStack {
            HStack {
                Text("Offline watch").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }.padding()
            Form {
                Section {
                    Text(video.title)
                    if loading {
                        ProgressView("Loading available streams…")
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { reload += 1 }
                    } else {
                        selections
                        if let tracks {
                            if let size = OfflineSelection.estimatedBytes(for: tracks) {
                                Text("Estimated media size: \(size.formatted(.byteCount(style: .file)))").font(.caption)
                            }
                            if translates {
                                Text("Translation size will be known after it is prepared.").font(.caption)
                            }
                        }
                    }
                } footer: {
                    Text("Downloads only the selected video and audio. You can add other tracks later in Library.")
                }
                Button("Download") {
                    guard let tracks else { return }
                    OfflineCoordinator.shared.enqueue(video: video, tracks: tracks)
                    dismiss()
                }
                .disabled(loading || tracks == nil)
                .accessibilityIdentifier(AccessibilityID.offlineSelectionDownload)
            }
            #if !os(tvOS)
            .pickerStyle(.menu)
            #endif
        }
        .task(id: reload) {
            loading = true
            do {
                let loaded = try await OfflineCoordinator.shared.catalog(video: video)
                try Task.checkCancellation()
                catalog = loaded
                videoID = videos.first { $0.videoSize?.height == 720 && $0.codec == .h264 }?.id ?? videos.first?.id
                audioID = preferredAudioID
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
    private var selections: some View {
        Group {
            Picker("Video stream", selection: $videoID) {
                ForEach(videos) { track in
                    Text(track.videoChoiceLabel + (track.kind == .hls ? " · HLS" : " · MP4")).tag(Optional(track.id))
                }
            }.accessibilityIdentifier(AccessibilityID.offlineSelectionVideo)
            Picker("Audio track", selection: $audioID) {
                ForEach(audio) { track in
                    Text(track.audioLabel ?? track.label).tag(Optional(track.id))
                }
            }.accessibilityIdentifier(AccessibilityID.offlineSelectionAudio)
            if audio.isEmpty { Text("No compatible audio track is available for this video stream.") }
            Toggle("Yandex translation", isOn: $translates)
                .accessibilityIdentifier(AccessibilityID.offlineSelectionTranslate)
            if translates {
                Picker("Translation language", selection: $language) {
                    ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                        Text(Locale.current.localizedString(forLanguageCode: language) ?? language).tag(language)
                    }
                }.accessibilityIdentifier(AccessibilityID.offlineSelectionLanguage)
            }
        }
    }
}
