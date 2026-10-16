import Foundation

// MARK: - HLS Master Manifest Parser
//
// Parses an HLS master playlist (M3U8) and returns a map of stream height → variant URL.
// Extracted from PlaybackQualityManager.fetchHLSVariantURLs (task #133, SRP-1).
//
// On iOS/macOS the parser prefers the H.264 (avc1) variant when both HEVC and H.264
// are present at the same resolution. On tvOS the first-seen variant is kept as-is
// (tvOS hardware decoders handle HEVC efficiently with lower power consumption).

/// Parses `manifestText` as an HLS master playlist and returns a map of
/// stream height (e.g. 1080) → absolute variant playlist URL.
///
/// - Parameters:
///   - manifestText: The raw text content of the `.m3u8` master playlist.
///   - baseURL: Base URL used to resolve relative URIs in the manifest.
/// - Returns: Dictionary mapping height in pixels to the best variant URL for that height.
public func parseHLSMasterManifest(_ manifestText: String, baseURL: URL) -> [Int: URL] {
    var variants: [Int: URL] = [:]
    var variantIsH264: [Int: Bool] = [:]
    for format in parseHLSVideoFormats(manifestText, baseURL: baseURL) {
        let height = format.height
        if variants[height] == nil {
            variants[height] = format.url
            variantIsH264[height] = format.videoCodec == .h264
        } else {
            #if !os(tvOS)
            if !(variantIsH264[height] ?? false), format.videoCodec == .h264 {
                variants[height] = format.url
                variantIsH264[height] = true
            }
            #endif
        }
    }
    return variants
}

/// Keeps codec alternatives at the same resolution so selection uses the actual HLS ladder.
public func parseHLSVideoFormats(_ manifest: String, baseURL: URL) -> [VideoFormat] {
    var formats: [VideoFormat] = []
    var pending: VideoFormat?
    for line in manifest.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            pending = nil
            let attributes = trimmed.dropFirst("#EXT-X-STREAM-INF:".count).split(separator: ",")
            func attribute(_ name: String) -> String? {
                attributes.first(where: { $0.hasPrefix(name + "=") })
                    .map { String($0.dropFirst(name.count + 1)) }
            }
            let dimensions = attribute("RESOLUTION")?.split(separator: "x").compactMap { Int($0) } ?? []
            guard dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 else { continue }
            let codecs = extractQuotedHLSAttribute("CODECS", from: trimmed) ?? ""
            let fps = attribute("FRAME-RATE").flatMap(Double.init).flatMap { Int(exactly: $0.rounded()) } ?? 30
            pending = VideoFormat(
                label: "\(dimensions[1])p", width: dimensions[0], height: dimensions[1], fps: fps,
                mimeType: "video/mp4; codecs=\"\(codecs)\"", bitrate: attribute("BANDWIDTH").flatMap(Int.init))
        } else if trimmed.hasPrefix("#") {
            pending = nil
        } else if !trimmed.isEmpty, var format = pending {
            format.url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            if format.url != nil { formats.append(format) }
            pending = nil
        }
    }
    return formats
}

/// Parses a map of stream height → variant URL from the HLS master manifest for a
/// specific dubbed-audio content ID. Used by switchHLSLanguage to update hlsVariantURLs.
/// If `contentID` is nil, returns original-audio variant URLs (no YT-EXT-AUDIO-CONTENT-ID).
public func parseHLSVariantURLsForLanguage(
    _ contentID: String?,
    from manifest: String,
    baseURL: URL
) -> [Int: URL] {
    let lines = manifest.components(separatedBy: "\n")
    var result: [Int: URL] = [:]
    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#EXT-X-STREAM-INF:") {
            let hasContentID = line.contains("YT-EXT-AUDIO-CONTENT-ID=")
            let matches: Bool
            if let lang = contentID {
                matches =
                    line.contains("YT-EXT-AUDIO-CONTENT-ID=\"\(lang)\"")
                    || line.contains("YT-EXT-AUDIO-CONTENT-ID=\(lang)")
            } else {
                matches = !hasContentID
            }
            guard matches else {
                i += 2
                continue
            }

            var height = 0
            if let resRange = line.range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression) {
                let resPart = String(line[resRange])
                if let h = resPart.components(separatedBy: "x").last.flatMap(Int.init) {
                    height = h
                }
            }
            i += 1
            while i < lines.count {
                let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && !candidate.hasPrefix("#") { break }
                i += 1
            }
            if i < lines.count, height > 0 {
                let uriLine = lines[i].trimmingCharacters(in: .whitespaces)
                let resolved: URL?
                if uriLine.hasPrefix("http://") || uriLine.hasPrefix("https://") {
                    resolved = URL(string: uriLine)
                } else {
                    let baseDir = baseURL.deletingLastPathComponent()
                    resolved = URL(string: uriLine, relativeTo: baseDir).map { $0.absoluteURL }
                }
                if let url = resolved { result[height] = url }
            }
        }
        i += 1
    }
    return result
}

/// Parses an HLS master M3U8 manifest and returns a map of stream height → variant URL
/// for all streams present. Handles both absolute and relative URIs.
/// Returns one URL per quality level — the first variant seen per height (original audio when
/// available, first dubbed entry as fallback when the manifest omits no-CONTENT-ID variants).
public func parseHLSAllVariants(from manifest: String, baseURL: URL) -> [Int: URL] {
    let lines = manifest.components(separatedBy: "\n")
    var result: [Int: URL] = [:]
    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#EXT-X-STREAM-INF:") {
            var height = 0
            if let resRange = line.range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression) {
                let resPart = String(line[resRange])
                if let h = resPart.components(separatedBy: "x").last.flatMap(Int.init) {
                    height = h
                }
            }
            i += 1
            while i < lines.count {
                let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && !candidate.hasPrefix("#") { break }
                i += 1
            }
            if i < lines.count, height > 0 {
                let uriLine = lines[i].trimmingCharacters(in: .whitespaces)
                let resolved: URL?
                if uriLine.hasPrefix("http://") || uriLine.hasPrefix("https://") {
                    resolved = URL(string: uriLine)
                } else {
                    let baseDir = baseURL.deletingLastPathComponent()
                    resolved = URL(string: uriLine, relativeTo: baseDir).map { $0.absoluteURL }
                }
                if let url = resolved, result[height] == nil {
                    // First entry per height wins — for YouTube's manifest order
                    // (original first, then dubbed per quality), this naturally
                    // selects the original audio variant.
                    result[height] = url
                }
            }
        }
        i += 1
    }
    return result
}

/// Parses an HLS master M3U8 manifest and returns the URL of the best stream at ≥ `minHeight`.
/// Handles both absolute URIs and relative paths (resolved against `baseURL`).
public func parseHLSBestVariant(from manifest: String, baseURL: URL, minHeight: Int) -> URL? {
    let lines = manifest.components(separatedBy: "\n")
    var bestHeight = 0
    var bestURL: URL?
    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#EXT-X-STREAM-INF:") {
            // No CONTENT-ID guard needed: the `height > bestHeight` condition naturally
            // selects the first entry per quality level (original audio in YouTube's
            // manifest order, or the first dubbed entry if no original exists).
            // Extract height from RESOLUTION=WxH
            var height = 0
            if let resRange = line.range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression) {
                let resPart = String(line[resRange])  // "RESOLUTION=1280x720"
                if let h = resPart.components(separatedBy: "x").last.flatMap(Int.init) {
                    height = h
                }
            }
            // Skip to next non-empty, non-comment line (the URI)
            i += 1
            while i < lines.count {
                let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && !candidate.hasPrefix("#") { break }
                i += 1
            }
            if i < lines.count, height >= minHeight, height > bestHeight {
                let uriLine = lines[i].trimmingCharacters(in: .whitespaces)
                let resolved: URL?
                if uriLine.hasPrefix("http://") || uriLine.hasPrefix("https://") {
                    resolved = URL(string: uriLine)
                } else {
                    // Relative URI — resolve against the directory of the master manifest URL
                    let baseDir = baseURL.deletingLastPathComponent()
                    resolved = URL(string: uriLine, relativeTo: baseDir).map { $0.absoluteURL }
                }
                if let url = resolved {
                    bestHeight = height
                    bestURL = url
                }
            }
        }
        i += 1
    }
    return bestURL
}

/// Produces an AVFoundation-safe HLS master while preserving separate audio renditions.
/// YouTube's VisionOS master mixes H.264 and VP9 variants; tvOS may select an unsupported
/// VP9 entry even when resolution hints are set. Filtering the master (rather than loading
/// a video-only variant) keeps `EXT-X-MEDIA` audio groups and removes incompatible video.
public func filterHLSMasterManifest(
    _ manifest: String,
    maximumHeight: Int?,
    videoCodecs: [String]
) -> String {
    let lines = manifest.components(separatedBy: .newlines)
    var output: [String] = []
    var shouldDropNextURI = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if shouldDropNextURI {
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                shouldDropNextURI = false
            } else if trimmed.hasPrefix("#") {
                output.append(line)
                continue
            } else {
                shouldDropNextURI = false
                continue
            }
        }

        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            let height: Int? =
                trimmed
                .range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression)
                .map { String(trimmed[$0]) }
                .flatMap { $0.components(separatedBy: "x").last }
                .flatMap(Int.init)
            let codecMatches = videoCodecs.contains { trimmed.localizedCaseInsensitiveContains($0) }
            guard codecMatches, let height, height <= maximumHeight ?? .max else {
                shouldDropNextURI = true
                continue
            }
            output.append(line)
            continue
        }

        if trimmed.hasPrefix("#EXT-X-MEDIA:"),
            trimmed.localizedCaseInsensitiveContains("TYPE=AUDIO"),
            hlsMediaLineIsOriginalAudio(trimmed)
        {
            if trimmed.contains("DEFAULT=NO") {
                output.append(line.replacingOccurrences(of: "DEFAULT=NO", with: "DEFAULT=YES"))
            } else if !trimmed.contains("DEFAULT=") {
                output.append(line + ",DEFAULT=YES")
            } else {
                output.append(line)
            }
            continue
        }

        output.append(line)
    }

    return output.joined(separator: "\n")
}

/// The original-language audio rendition of a YouTube HLS master (the first one, which is
/// also the lowest-bitrate group), else the first audio rendition.
public func hlsOriginalAudioPlaylistURL(in manifest: String, baseURL: URL) -> URL? {
    let audio = manifest.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO") }
    guard let line = audio.first(where: hlsMediaLineIsOriginalAudio) ?? audio.first,
        let uri = extractQuotedHLSAttribute("URI", from: line)
    else { return nil }
    return URL(string: uri, relativeTo: baseURL)?.absoluteURL
}

/// Every media URL of an HLS media playlist in play order: the `EXT-X-MAP` init segment
/// (when present), then the segments. Each URL appears once: a byte-range playlist repeats
/// one file per `EXT-X-BYTERANGE` slice, and fetched once that file is the whole stream.
public func hlsSegmentURLs(in playlist: String, baseURL: URL) -> [URL] {
    var seen = Set<URL>()
    return playlist.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .compactMap { line -> String? in
            if line.hasPrefix("#EXT-X-MAP:") { return extractQuotedHLSAttribute("URI", from: line) }
            return line.isEmpty || line.hasPrefix("#") ? nil : line
        }
        .compactMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        .filter { seen.insert($0).inserted }
}

/// A packed-audio HLS segment without its leading ID3v2 timestamp tag. Concatenated with the
/// tags, YouTube's AAC segments leave ID3 blocks mid-stream and Yandex never finishes
/// decoding the upload; stripped, they form one plain ADTS AAC stream.
public func strippingLeadingID3Tag(_ segment: Data) -> Data {
    let header = [UInt8](segment.prefix(10))
    guard header.count == 10, header.starts(with: Array("ID3".utf8)) else { return segment }
    // Size is a 28-bit "syncsafe" integer: 7 bits per byte.
    let size = header[6...9].reduce(0) { $0 << 7 | Int($1 & 0x7F) }
    return Data(segment.dropFirst(min(10 + size, segment.count)))  // rebased: indices start at 0
}

private func hlsMediaLineIsOriginalAudio(_ line: String) -> Bool {
    if line.localizedCaseInsensitiveContains("original")
        && !line.localizedCaseInsensitiveContains("dubbed")
    {
        return true
    }
    guard let encoded = extractQuotedHLSAttribute("YT-EXT-XTAGS", from: line) else {
        return false
    }
    let padded = encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: padded) else { return false }
    return data.range(of: Data("original".utf8)) != nil
        && data.range(of: Data("dubbed".utf8)) == nil
}
