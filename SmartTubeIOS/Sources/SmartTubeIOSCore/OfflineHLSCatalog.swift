import Foundation

/// Each choice binds one video rendition and, when present, one member of its external audio group.
public func offlineHLSVariants(
    _ manifest: String, baseURL: URL, duration: TimeInterval? = nil
) -> [(OfflineTrack, URL)] {
    let languages = parseHLSAudioLanguages(from: manifest)
    let audioLines = manifest.components(separatedBy: .newlines).filter {
        $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO")
    }
    let groupedLanguages = parseHLSAudioLanguages(
        from: audioLines.map {
            $0.replacingOccurrences(of: "#EXT-X-MEDIA:", with: "#EXT-X-STREAM-INF:")
        }.joined(separator: "\n"))
    var result: [(OfflineTrack, URL)] = []
    var tag: String?
    for raw in manifest.components(separatedBy: .newlines) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#EXT-X-STREAM-INF:") {
            tag = line
            continue
        }
        guard !line.isEmpty, !line.hasPrefix("#"), let attributes = tag else { continue }
        tag = nil
        guard let codecs = extractQuotedHLSAttribute("CODECS", from: attributes),
            codecs.contains("mp4a") || codecs.contains("ac-3") || codecs.contains("ec-3"),
            let format = parseHLSVideoFormats(attributes + "\n" + line, baseURL: baseURL).first,
            let url = format.url, url.scheme == "https"
        else { continue }
        let contentID = extractQuotedHLSAttribute("YT-EXT-AUDIO-CONTENT-ID", from: attributes)
        let language = languages.first { $0.contentID == contentID }
        var track = OfflineTrack(
            id: "hls-\(format.height)-\(format.codecShortLabel)-\(format.fps)-\(contentID ?? "default")",
            kind: .hls, label: "\(format.qualityLabel) · \(format.codecShortLabel)",
            language: language?.languageCode, hasAudio: true)
        track.videoSize = OfflineVideoSize(width: format.width, height: format.height)
        track.fps = format.fps
        track.codec = format.videoCodec
        track.hlsPeakBitRate = format.bitrate.map(Double.init)
        // BANDWIDTH is a peak, not a file-size estimate (some YouTube peaks exceed the average tenfold).
        let average = attributes.split(separator: ",").first { $0.hasPrefix("AVERAGE-BANDWIDTH=") }
            .flatMap { Int($0.dropFirst("AVERAGE-BANDWIDTH=".count)) }
        track.estimatedBytes = OfflineTrack.estimatedSize(bitrate: average, duration: duration)
        if let group = extractQuotedHLSAttribute("AUDIO", from: attributes) {
            for audio in audioLines where extractQuotedHLSAttribute("GROUP-ID", from: audio) == group {
                guard let name = extractQuotedHLSAttribute("NAME", from: audio),
                    let uri = extractQuotedHLSAttribute("URI", from: audio),
                    URL(string: uri, relativeTo: baseURL)?.absoluteURL.scheme == "https"
                else { continue }
                let language = extractQuotedHLSAttribute("LANGUAGE", from: audio)
                let id = extractQuotedHLSAttribute("YT-EXT-AUDIO-CONTENT-ID", from: audio) ?? name
                let audioLabel =
                    name + " · " + (codecs.contains("mp4a.40.5") ? "HE-AAC" : codecs.contains("mp4a") ? "AAC" : "Dolby")
                var choice = OfflineTrack(
                    id: track.id + "-\(group)-\(id)", kind: .hls,
                    label: track.label + " · " + audioLabel, language: language, hasAudio: true)
                choice.videoSize = track.videoSize
                choice.fps = track.fps
                choice.codec = track.codec
                choice.estimatedBytes = track.estimatedBytes
                choice.hlsPeakBitRate = track.hlsPeakBitRate
                choice.audioLabel = audioLabel
                choice.isOriginalAudio =
                    groupedLanguages.first { $0.contentID == id }?.isOriginal
                    ?? audio.contains("DEFAULT=YES")
                choice.hlsAudioName = name
                if !result.contains(where: { $0.0.id == choice.id }) { result.append((choice, url)) }
            }
        } else {
            let audioLabel =
                language.map { "\($0.name) · \($0.isOriginal ? "Original" : "Dubbed")" } ?? "Original · included audio"
            track.audioLabel = audioLabel
            track.isOriginalAudio = language?.isOriginal ?? true
            // Keep the pre-selection catalog label and ID compatible with saved muxed variants.
            track.label += " · " + audioLabel
            if !result.contains(where: { $0.0.id == track.id }) { result.append((track, url)) }
        }
    }
    return result
}
