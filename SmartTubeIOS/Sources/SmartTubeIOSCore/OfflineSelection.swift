import Foundation

public extension OfflineTrack {
    var videoChoiceID: String {
        guard kind == .hls, let videoSize, let codec else { return id }
        return "hls-\(videoSize.width)-\(videoSize.height)-\(fps ?? 30)-\(codec.rawValue)"
    }
    var videoChoiceLabel: String {
        guard let videoSize, let codec else { return label }
        return "\(videoSize.height)p\((fps ?? 30) > 30 ? String(fps ?? 30) : "") · \(codec.label)"
    }
    static func estimatedSize(bitrate: Int?, duration: TimeInterval?) -> Int64? {
        guard let bitrate, bitrate > 0, let duration, duration.isFinite, duration > 0 else { return nil }
        return Int64(exactly: (Double(bitrate) * duration / 8).rounded(.up))
    }
}

/// One video (or one muxed HLS rendition), one companion audio, and optional voice-over.
public enum OfflineSelection {
    public static func defaultLanguage(preference: String?, locale: Locale = .current) -> String? {
        guard preference != "original" else { return nil }
        return Locale.Language(identifier: preference ?? locale.identifier).languageCode?.identifier
    }

    public static func preferredAudio(in options: [OfflineTrack], language: String?) -> OfflineTrack? {
        let preferred = language.flatMap { Locale.Language(identifier: $0).languageCode?.identifier }
        func rank(_ track: OfflineTrack) -> Int {
            if let preferred, let code = track.language,
                Locale.Language(identifier: code).languageCode?.identifier == preferred
            {
                return 0
            }
            return track.isOriginalAudio == true ? 1 : 2
        }
        func bitrate(_ track: OfflineTrack) -> Double {
            guard let value = track.bitrate.map(Double.init) ?? track.hlsPeakBitRate,
                value.isFinite, value > 0
            else { return .infinity }
            return value
        }
        return options.min {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if bitrate($0) != bitrate($1) { return bitrate($0) < bitrate($1) }
            return $0.id < $1.id
        }
    }

    public static func estimatedBytes(for tracks: [OfflineTrack]) -> Int64? {
        var total: Int64 = 0
        for track in tracks where track.kind != .translation {
            guard let size = track.estimatedBytes, size > 0 else { return nil }
            let sum = total.addingReportingOverflow(size)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total > 0 ? total : nil
    }

    public static func videos(in catalog: [OfflineTrack]) -> [OfflineTrack] {
        var seen = Set<String>()
        return catalog.filter { [.video, .hls].contains($0.kind) && seen.insert($0.videoChoiceID).inserted }
    }
    public static func audio(for video: OfflineTrack, in catalog: [OfflineTrack]) -> [OfflineTrack] {
        if video.kind == .hls {
            return catalog.filter { $0.kind == .hls && $0.videoChoiceID == video.videoChoiceID }
        }
        return (video.hasAudio ? [video] : []) + catalog.filter { $0.kind == .audio }
    }
    public static func tracks(
        video: OfflineTrack, audio: OfflineTrack, translation: String?, catalog: [OfflineTrack]
    ) throws -> [OfflineTrack] {
        guard catalog.contains(video), Self.audio(for: video, in: catalog).contains(audio) else {
            throw OfflineLibraryError.unavailable
        }
        var tracks = video.kind == .hls ? [audio] : video.id == audio.id ? [video] : [video, audio]
        if let translation { tracks.append(.translation(translation)) }
        return tracks
    }
}
