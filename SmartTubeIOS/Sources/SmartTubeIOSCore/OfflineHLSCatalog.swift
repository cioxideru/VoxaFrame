import Foundation

/// Only standalone muxed variants can be downloaded without losing an external audio group.
public func offlineHLSVariants(_ manifest: String, baseURL: URL) -> [(OfflineTrack, URL)] {
    let languages = parseHLSAudioLanguages(from: manifest)
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
        guard extractQuotedHLSAttribute("AUDIO", from: attributes) == nil,
            let codecs = extractQuotedHLSAttribute("CODECS", from: attributes),
            codecs.contains("mp4a") || codecs.contains("ac-3") || codecs.contains("ec-3"),
            let format = parseHLSVideoFormats(attributes + "\n" + line, baseURL: baseURL).first,
            let url = format.url, url.scheme == "https"
        else { continue }
        let contentID = extractQuotedHLSAttribute("YT-EXT-AUDIO-CONTENT-ID", from: attributes)
        let language = languages.first { $0.contentID == contentID }
        let audioLabel = language.map { "\($0.name) · \($0.isOriginal ? "Original" : "Dubbed")" } ?? "Included audio"
        let track = OfflineTrack(
            id: "hls-\(format.height)-\(format.codecShortLabel)-\(format.fps)-\(contentID ?? "default")",
            kind: .hls, label: "\(format.qualityLabel) · \(format.codecShortLabel) · \(audioLabel)",
            language: language?.languageCode, hasAudio: true)
        if !result.contains(where: { $0.0.id == track.id }) { result.append((track, url)) }
    }
    return result
}
