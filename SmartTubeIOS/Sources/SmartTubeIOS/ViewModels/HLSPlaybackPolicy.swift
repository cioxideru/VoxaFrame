import SmartTubeIOSCore
import VideoToolbox

/// Client-specific HLS settings used for both initial playback and quality changes.
struct HLSPlaybackPolicy: Equatable, Sendable {
    let userAgent: String
    let maximumHeight: Int?
    // HLS specification names the multivariant playlist a master playlist. swiftlint:disable:next inclusive_language
    let filtersMasterManifest: Bool
    /// Video codecs the master manifest is filtered to (`Self.vp9`, `Self.h264`); empty keeps it as is.
    let videoCodecs: [String]

    /// HLS `CODECS` prefixes of the two ladders the VISIONOS client serves.
    static let h264 = "avc1"
    static let vp9 = "vp09"

    /// iOS/tvOS 26.2+ ship a VP9 decoder that apps must opt into. With it, the VISIONOS
    /// ladder's VP9 variants (1440p, 2160p) play natively; without it, H.264 tops out at 1080p.
    static let isVP9DecodingAvailable: Bool = {
        if #available(iOS 26.2, tvOS 26.2, macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        }
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
    }()

    /// `vp9Enabled` / `h264Enabled` are the user's codec settings. VP9 needs a decoder; when it
    /// is off or missing, the H.264 ladder plays even if its setting is off.
    static func resolve(
        label: String, isHLS: Bool, vp9Enabled: Bool = true, h264Enabled: Bool = false,
        vp9Available: Bool = isVP9DecodingAvailable
    ) -> Self {
        guard isHLS else {
            return Self(
                userAgent: "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
                maximumHeight: nil,
                filtersMasterManifest: false,
                videoCodecs: []
            )
        }
        if label.localizedCaseInsensitiveContains("visionos") {
            let vp9 = vp9Enabled && vp9Available
            return Self(
                userAgent: InnerTubeClients.VisionOS.userAgent,
                maximumHeight: vp9 ? nil : InnerTubeClients.VisionOS.maximumHLSHeight,
                filtersMasterManifest: true,
                videoCodecs: (vp9 ? [Self.vp9] : []) + (h264Enabled || !vp9 ? [Self.h264] : [])
            )
        }
        if label.contains("WebSafari") {
            return Self(
                userAgent: InnerTubeClients.WebSafari.userAgent,
                maximumHeight: nil,
                filtersMasterManifest: false,
                videoCodecs: []
            )
        }
        return Self(
            userAgent: "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
            maximumHeight: nil,
            filtersMasterManifest: false,
            videoCodecs: []
        )
    }

    func cappedHeight(requested: Int?) -> Int? {
        guard let maximumHeight else { return requested }
        return min(requested ?? maximumHeight, maximumHeight)
    }

    /// Quality picker rows under this policy: the VP9 ladder's rows and/or the current H.264 rows
    /// up to the H.264 ladder's top, VP9 first at equal height; the current rows when unfiltered.
    func pickerFormats(
        from formats: [SmartTubeIOSCore.VideoFormat], current: [SmartTubeIOSCore.VideoFormat]
    ) -> [SmartTubeIOSCore.VideoFormat] {
        guard !videoCodecs.isEmpty else { return current }
        let vp9Rows = videoCodecs.contains(Self.vp9) ? Self.vp9PickerFormats(formats) : []
        let h264Rows =
            videoCodecs.contains(Self.h264)
            ? current.filter {
                $0.mimeType.contains(Self.h264) && $0.height <= InnerTubeClients.VisionOS.maximumHLSHeight
            }
            : []
        return (vp9Rows + h264Rows).sorted {
            $0.height != $1.height ? $0.height > $1.height : Self.videoCodec(ofMimeType: $0.mimeType) == Self.vp9
        }
    }

    /// The ladder codec of an adaptive format: `video/webm; codecs="vp9"` → `vp9`, `avc1.…` → `h264`.
    static func videoCodec(ofMimeType mimeType: String) -> String? {
        if mimeType.contains(h264) { return h264 }
        if mimeType.contains("vp9") || mimeType.contains(vp9) { return vp9 }
        return nil
    }

    /// Quality picker rows for a VP9 ladder: YouTube lists VP9 as `video/webm; codecs="vp9"`
    /// adaptive formats, one row per height (highest fps wins). Switching caps the master by height.
    static func vp9PickerFormats(_ formats: [SmartTubeIOSCore.VideoFormat]) -> [SmartTubeIOSCore.VideoFormat] {
        Dictionary(grouping: formats.filter { $0.mimeType.contains("vp9") && $0.height > 0 }, by: \.height)
            .compactMap { $0.value.max { ($0.fps, $0.bitrate ?? 0) < ($1.fps, $1.bitrate ?? 0) } }
            .sorted { $0.height > $1.height }
    }
}
