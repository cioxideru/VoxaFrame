import Foundation
import SmartTubeIOSCore

/// Saved selections and catalog labels, independent of the player and device capability queries.
enum OfflineDetailPresentation {
    struct Selection: Equatable {
        var videoID: String?
        var audioID: String?
        private(set) var translationID: String?
        private(set) var translationChosen = false
        private var entryID: String?

        mutating func update(entry: OfflineEntry) {
            if entryID != entry.id {
                self = Self()
                entryID = entry.id
            }
            videoID = video(in: entry.assets)?.id
            if !entry.assets.contains(where: { $0.track.kind == .audio && $0.id == audioID }) { audioID = nil }
            if !entry.assets.contains(where: { $0.track.kind == .translation && $0.id == translationID }) {
                translationID = nil
            }
            if !translationChosen && translationID == nil {
                translationID = OfflineDetailPresentation.defaultTranslation(in: entry.assets)
            }
        }

        mutating func chooseTranslation(_ id: String?) {
            translationID = id
            translationChosen = true
        }

        func video(in assets: [OfflineAsset]) -> OfflineAsset? {
            let videos = assets.filter { [.video, .hls].contains($0.track.kind) }
            return videos.first { $0.id == videoID } ?? videos.first
        }

        func audio(for video: OfflineAsset, in assets: [OfflineAsset]) -> OfflineAsset? {
            guard video.track.kind != .hls else { return nil }
            let audio = assets.filter { $0.track.kind == .audio }
            return audio.first { $0.id == audioID } ?? (video.track.hasAudio ? nil : audio.first)
        }

        func translation(in assets: [OfflineAsset]) -> OfflineAsset? {
            assets.first { $0.track.kind == .translation && $0.id == translationID }
        }
    }

    enum Sound: Equatable {
        case original, inFile, audio(String), voiceOver(String), missingAudio
    }

    struct Summary: Equatable {
        let quality: String
        let sound: Sound

        var text: String {
            let description: String =
                switch sound {
                case .original: String(localized: "Original audio", bundle: .module)
                case .inFile: String(localized: "Sound in video file", bundle: .module)
                case .audio(let language): String(localized: "\(language) audio", bundle: .module)
                case .voiceOver(let language): String(localized: "\(language) voice-over", bundle: .module)
                case .missingAudio: String(localized: "Audio not downloaded", bundle: .module)
                }
            return "\(quality) · \(description)"
        }
    }

    struct VideoGroup: Identifiable {
        let height: Int
        let tracks: [OfflineTrack]
        let recommendedID: String?
        var id: Int { height }
        var title: String { height > 0 ? "\(height)p" : String(localized: "Other formats", bundle: .module) }
    }

    struct Catalog {
        let videoGroups: [VideoGroup]
        let audio: [OfflineTrack]
        let translationLanguages: [String]
    }

    struct AudioOption: Identifiable {
        let id: String?
        let label: String
    }

    // Prefer the broadly supported formats, then hardware-decoded alternatives.
    private static let codecOrder: [VideoCodec] = [.h264, .hevc, .av1, .vp9]

    static func defaultTranslation(in assets: [OfflineAsset]) -> String? {
        let translations = assets.filter { $0.track.kind == .translation }
        return translations.count == 1 ? translations.first?.id : nil
    }

    static func summary(
        video: OfflineAsset, selection: Selection, assets: [OfflineAsset], locale: Locale = .current
    ) -> Summary {
        let audio = selection.audio(for: video, in: assets)
        let sound: Sound
        if let translation = selection.translation(in: assets) {
            sound = .voiceOver(languageName(translation.track.language, locale: locale))
        } else if !video.track.hasAudio, audio == nil {
            sound = .missingAudio
        } else if let audio {
            sound =
                audio.track.isOriginalAudio == true
                ? .original : .audio(languageName(audio.track.language, locale: locale))
        } else if video.track.isOriginalAudio == true {
            sound = .original
        } else if let language = video.track.language, !language.isEmpty {
            sound = .audio(languageName(video.track.language, locale: locale))
        } else {
            sound = .inFile
        }
        return Summary(quality: qualityLabel(video.track), sound: sound)
    }

    static func catalog(
        _ available: [OfflineTrack], saved: [OfflineAsset], targetLanguages: [String],
        hardwareCodecs: Set<VideoCodec>, locale: Locale = .current
    ) -> Catalog {
        let savedIDs = Set(saved.map(\.id))
        let unsaved = available.filter { !savedIDs.contains($0.id) }
        let groups = Dictionary(grouping: unsaved.filter { [.video, .hls].contains($0.kind) }, by: height)
        let videos = groups.keys.sorted(by: >).map { height in
            let tracks = (groups[height] ?? []).sorted { lhs, rhs in
                let left = codecRank(lhs, hardwareCodecs: hardwareCodecs)
                let right = codecRank(rhs, hardwareCodecs: hardwareCodecs)
                if left != right { return left < right }
                if (lhs.isOriginalAudio == true) != (rhs.isOriginalAudio == true) {
                    return lhs.isOriginalAudio == true
                }
                if (lhs.fps ?? 0) != (rhs.fps ?? 0) { return (lhs.fps ?? 0) > (rhs.fps ?? 0) }
                return lhs.id < rhs.id
            }
            return VideoGroup(
                height: height, tracks: tracks,
                recommendedID: tracks.first { isPlayable($0, hardwareCodecs: hardwareCodecs) }?.id)
        }
        let savedLanguages = Set(saved.filter { $0.track.kind == .translation }.compactMap { $0.track.language })
        return Catalog(
            videoGroups: videos, audio: sortedAudio(unsaved.filter { $0.kind == .audio }, locale: locale),
            translationLanguages: targetLanguages.filter { !savedLanguages.contains($0) }.sorted {
                languageName($0, locale: locale) < languageName($1, locale: locale)
            })
    }

    static func sortedAudio(_ tracks: [OfflineTrack], locale: Locale = .current) -> [OfflineTrack] {
        tracks.sorted { lhs, rhs in
            if (lhs.isOriginalAudio == true) != (rhs.isOriginalAudio == true) { return lhs.isOriginalAudio == true }
            let left = languageName(lhs.language, locale: locale)
            let right = languageName(rhs.language, locale: locale)
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    static func languageName(_ code: String?, locale: Locale = .current) -> String {
        guard let code, !code.isEmpty else { return String(localized: "Unknown language", bundle: .module) }
        return locale.localizedString(forIdentifier: code) ?? code
    }

    static func audioLabel(_ track: OfflineTrack, locale: Locale = .current) -> String {
        let language =
            track.language?.isEmpty == false
            ? languageName(track.language, locale: locale) : String(localized: "Audio", bundle: .module)
        switch track.isOriginalAudio {
        case .some(true): return String(localized: "\(language) · Original", bundle: .module)
        case .some(false): return String(localized: "\(language) · Dubbed", bundle: .module)
        case .none: return language
        }
    }

    static func audioOptions(
        for video: OfflineTrack, saved: [OfflineTrack], locale: Locale = .current
    ) -> [AudioOption] {
        let tracks = sortedAudio(saved, locale: locale)
        let labels = tracks.map { track in
            track.isOriginalAudio == false || track.language?.isEmpty != false
                ? audioLabel(track, locale: locale) : languageName(track.language, locale: locale)
        }
        let detailed = zip(tracks, labels).map { track, label in
            track.language?.isEmpty != false || labels.filter { $0 == label }.count > 1
                ? [label, audioDetail(track)].compactMap { $0 }.joined(separator: " · ") : label
        }
        var occurrences: [String: Int] = [:]
        var options = zip(tracks, detailed).map { track, label in
            occurrences[label, default: 0] += 1
            let unique =
                detailed.filter { $0 == label }.count > 1 ? "\(label) · \(occurrences[label, default: 0])" : label
            return AudioOption(id: track.id, label: unique)
        }
        if video.hasAudio || video.kind == .hls {
            var label = String(localized: "Sound in video file", bundle: .module)
            if video.isOriginalAudio == true {
                label = String(localized: "Original", bundle: .module)
            } else if let language = video.language, !language.isEmpty {
                label = languageName(language, locale: locale)
            }
            if options.contains(where: { $0.label == label }) {
                label = String(localized: "\(label) · In video file", bundle: .module)
            }
            options.insert(AudioOption(id: nil, label: label), at: 0)
        }
        return options
    }

    static func audioDetail(_ track: OfflineTrack) -> String? {
        // Existing manifests keep the codec and bitrate in the final label component.
        let parts = track.label.components(separatedBy: " · ")
        return parts.count >= 2 ? parts.last : nil
    }

    static func isPlayable(_ track: OfflineTrack, hardwareCodecs: Set<VideoCodec>) -> Bool {
        guard let codec = codec(track) else { return false }
        return codec == .h264 || codec == .hevc || hardwareCodecs.contains(codec)
    }

    static func videoDetail(_ track: OfflineTrack, locale: Locale = .current) -> String {
        var parts = [codec(track)?.label ?? track.label]
        if let fps = track.fps, fps > 0 { parts.append(String(localized: "\(fps) fps", bundle: .module)) }
        if track.kind == .hls {
            parts.append("HLS")
            if track.language != nil { parts.append(audioLabel(track, locale: locale)) }
        }
        return parts.joined(separator: " · ")
    }

    static func savedVideoLabel(_ asset: OfflineAsset) -> String {
        var parts =
            height(asset.track) > 0
            ? [qualityLabel(asset.track), videoDetail(asset.track)] : [videoDetail(asset.track)]
        if let sizes = asset.savedVideoSizes, !sizes.isEmpty {
            parts.append(sizes.map { "\($0.width)×\($0.height)" }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private static func qualityLabel(_ track: OfflineTrack) -> String {
        let height = height(track)
        return height > 0 ? "\(height)p" : track.kind == .hls ? "HLS" : String(localized: "Video", bundle: .module)
    }

    private static func height(_ track: OfflineTrack) -> Int {
        // Older saved tracks and the loopback fixture may predate structured video metadata.
        track.videoSize?.height ?? Int(track.label.prefix(while: \.isNumber)) ?? 0
    }

    private static func codec(_ track: OfflineTrack) -> VideoCodec? {
        track.codec ?? codecOrder.first { track.label.contains($0.label) }
    }

    private static func codecRank(_ track: OfflineTrack, hardwareCodecs: Set<VideoCodec>) -> Int {
        let index = codec(track).flatMap { codecOrder.firstIndex(of: $0) } ?? codecOrder.count
        return (isPlayable(track, hardwareCodecs: hardwareCodecs) ? 0 : codecOrder.count) + index
    }
}
