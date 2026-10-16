import Foundation

/// User intent, independent of a video's temporary URLs and available quality ladder.
public struct VideoQualityPreference: Codable, Equatable, Sendable {
    public let height: Int?
    public let codec: VideoCodec?

    public static let auto = Self()

    public init(height: Int? = nil, codec: VideoCodec? = nil) {
        self.height = height.flatMap { $0 > 0 ? $0 : nil }
        self.codec = self.height == nil ? nil : codec
    }

    public init(format: VideoFormat?) {
        self.init(height: format?.height, codec: format?.videoCodec)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            height: try values.decodeIfPresent(Int.self, forKey: .height),
            codec: try? values.decodeIfPresent(VideoCodec.self, forKey: .codec))
    }

    /// Callers supply only formats supported by the active stream and device.
    public func bestMatch(in formats: [VideoFormat]) -> VideoFormat? {
        guard let height else { return nil }
        return formats.filter { $0.height > 0 }.min { lhs, rhs in
            let leftDistance = abs(lhs.height - height)
            let rightDistance = abs(rhs.height - height)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            if let codec {
                let leftMatch = lhs.videoCodec == codec
                let rightMatch = rhs.videoCodec == codec
                if leftMatch != rightMatch { return leftMatch }
            }
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            if lhs.fps != rhs.fps { return lhs.fps > rhs.fps }
            return (lhs.bitrate ?? 0) > (rhs.bitrate ?? 0)
        }
    }

    public func closestHeight(in heights: some Sequence<Int>) -> Int? {
        guard let height else { return nil }
        return heights.filter { $0 > 0 }.min {
            let leftDistance = abs($0 - height)
            let rightDistance = abs($1 - height)
            return leftDistance != rightDistance ? leftDistance < rightDistance : $0 < $1
        }
    }
}

public enum VideoCodec: String, Codable, Sendable {
    case h264 = "avc1"
    case vp9 = "vp09"
    case av1 = "av01"
    case hevc = "hvc1"

    public init?(mimeType: String) {
        if mimeType.contains(Self.h264.rawValue) {
            self = .h264
        } else if mimeType.contains(Self.vp9.rawValue) || mimeType.contains("vp9") {
            self = .vp9
        } else if mimeType.contains(Self.av1.rawValue) {
            self = .av1
        } else if mimeType.contains(Self.hevc.rawValue) || mimeType.contains("hev1") {
            self = .hevc
        } else {
            return nil
        }
    }

    public var label: String {
        switch self {
        case .h264: "H.264"
        case .vp9: "VP9"
        case .av1: "AV1"
        case .hevc: "HEVC"
        }
    }
}
