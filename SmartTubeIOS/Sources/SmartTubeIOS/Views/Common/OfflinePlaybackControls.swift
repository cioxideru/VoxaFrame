import SmartTubeIOSCore
import SwiftUI
import os

private let offlinePlaybackLog = Logger(subsystem: appSubsystem, category: "OfflinePlayback")

/// Keeps playback errors below the full row while controls occupy its trailing edge.
struct OfflinePlaybackControls<Content: View>: View {
    let entry: OfflineEntry
    let open: (Video) -> Void
    @ViewBuilder let content: Content
    @State private var coordinator = OfflineCoordinator.shared
    @State private var selection = OfflineDetailPresentation.Selection()
    @State private var showsOptions = false
    @State private var pendingVideo: Video?
    @State private var error: String?
    @State private var preparing = false

    private var video: OfflineAsset? { selection.video(in: entry.assets) }

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.s4) {
            HStack(spacing: VFSpace.s12) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                if let video {
                    VStack(spacing: VFSpace.s4) {
                        Button {
                            play(entry, asset: video)
                        } label: {
                            Label {
                                Text("Play", bundle: .module)
                            } icon: {
                                if preparing { ProgressView() } else { Image(systemName: AppSymbol.play) }
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: VFSpace.s20)
                        }
                        .accessibilityLabel(Text("Play", bundle: .module))
                        .accessibilityIdentifier(AccessibilityID.offlineLibraryPlay(entry.id))
                        Button {
                            showsOptions = true
                        } label: {
                            Image(systemName: AppSymbol.chevronDown)
                                .frame(minWidth: VFSpace.s20)
                        }
                        .accessibilityLabel(Text("Playback options", bundle: .module))
                        .accessibilityIdentifier(AccessibilityID.offlinePlayOptions(entry.id))
                    }
                    .buttonStyle(.vfProminent)
                    #if os(iOS)
                    .controlSize(.small)
                    #endif
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(preparing)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(VFColor.danger) }
        }
        .onChange(of: entry.assets.map(\.id), initial: true) { selection.update(entry: entry) }
        .sheet(
            isPresented: $showsOptions,
            onDismiss: {
                if let pendingVideo {
                    self.pendingVideo = nil
                    open(pendingVideo)
                }
            }, content: { options })
    }

    private var options: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.video.title).font(.headline)
                    watchWith(entry)
                }
                if let video {
                    Section {
                        Text(
                            OfflineDetailPresentation.summary(video: video, selection: selection, assets: entry.assets)
                                .text
                        )
                        .accessibilityIdentifier(AccessibilityID.offlinePlaySummary)
                        Button {
                            play(entry, asset: video)
                        } label: {
                            Label {
                                Text("Play", bundle: .module)
                            } icon: {
                                if preparing { ProgressView() } else { Image(systemName: AppSymbol.play) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.vfProminent)
                        .disabled(preparing)
                        .accessibilityIdentifier(AccessibilityID.offlinePlay(video.id))
                    }
                }
                if let error { Text(error).foregroundStyle(VFColor.danger) }
            }
            .accessibilityIdentifier(AccessibilityID.offlinePlaybackOptionsList)
            .navigationTitle(Text("Playback options", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showsOptions = false
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlinePlayOptionsClose)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 600, minHeight: 350, idealHeight: 500)
        #elseif os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    @ViewBuilder private func watchWith(_ entry: OfflineEntry) -> some View {
        let videos = entry.assets.filter { [.video, .hls].contains($0.track.kind) }
        let audio = entry.assets.filter { $0.track.kind == .audio }.map(\.track)
        let translations = entry.assets.filter { $0.track.kind == .translation }
        let video = selection.video(in: entry.assets)
        let includesAudio = video?.track.hasAudio == true || video?.track.kind == .hls
        let showsAudio = video != nil && !audio.isEmpty && (includesAudio || audio.count > 1)
        if videos.count > 1 || showsAudio || !translations.isEmpty {
            Group {
                if videos.count > 1 {
                    Picker(selection: $selection.videoID) {
                        ForEach(videos) { asset in
                            Text(OfflineDetailPresentation.savedVideoLabel(asset)).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Video", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineVideoPicker)
                    .accessibilityValue(video.map(OfflineDetailPresentation.savedVideoLabel) ?? "")
                }
                if showsAudio, let video {
                    Picker(
                        selection: Binding(
                            get: { selection.audio(for: video, in: entry.assets)?.id },
                            set: { selection.audioID = $0 }
                        )
                    ) {
                        ForEach(OfflineDetailPresentation.audioOptions(for: video.track, saved: audio)) { option in
                            Text(option.label).tag(option.id)
                        }
                    } label: {
                        Text("Audio", bundle: .module)
                    }
                    .disabled(video.track.kind == .hls)
                    .accessibilityIdentifier(AccessibilityID.offlineAudioPicker)
                    if video.track.kind == .hls {
                        Text("HLS uses the audio saved inside the video.", bundle: .module)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !translations.isEmpty {
                    Picker(
                        selection: Binding(get: { selection.translationID }, set: { selection.chooseTranslation($0) })
                    ) {
                        Text("Off", bundle: .module).tag(nil as String?)
                        ForEach(translations) { asset in
                            Text(OfflineDetailPresentation.languageName(asset.track.language)).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Voice-over (Yandex)", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineTranslationPicker)
                    .accessibilityValue(
                        selection.translation(in: entry.assets).map {
                            OfflineDetailPresentation.languageName($0.track.language)
                        } ?? String(localized: "Off", bundle: .module))
                }
            }
        }
    }

    private func play(_ entry: OfflineEntry, asset: OfflineAsset) {
        offlinePlaybackLog.notice("[offline-start] tap videoId=\(entry.id, privacy: .public)")
        let audio = selection.audio(for: asset, in: entry.assets)
        let translation = selection.translation(in: entry.assets)
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let video = try await coordinator.playbackVideo(
                    entry: entry, videoAsset: asset, audio: audio, translation: translation)
                if showsOptions {
                    pendingVideo = video
                    showsOptions = false
                } else {
                    open(video)
                }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
