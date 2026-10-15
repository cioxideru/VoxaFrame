import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("VisionOS Playback")
struct VisionOSPlaybackTests {

    @Test("client identity matches the current JS-less VisionOS client")
    func clientIdentity() {
        #expect(InnerTubeClients.VisionOS.name == "VISIONOS")
        #expect(InnerTubeClients.VisionOS.nameID == "101")
        #expect(InnerTubeClients.VisionOS.version == "1.04")
        #expect(InnerTubeClients.VisionOS.userAgent.hasPrefix("com.google.visionos.youtube/1.04("))
        #expect(InnerTubeClients.VisionOS.maximumHLSHeight == 1080)
    }

    @Test("watch-page parser decodes uppercase visitor data")
    func extractsUppercaseVisitorData() {
        let html = #"<script>ytcfg.set({"VISITOR_DATA":"Cgt2aXNpdG9yX2lk\u003d"});</script>"#
        #expect(extractYouTubeVisitorData(from: html) == "Cgt2aXNpdG9yX2lk=")
    }

    @Test("watch-page parser accepts lower-camel visitor data")
    func extractsLowerCamelVisitorData() {
        let html = #"<script>window.bootstrap={"visitorData":"visitor-token-123"};</script>"#
        #expect(extractYouTubeVisitorData(from: html) == "visitor-token-123")
    }

    @Test("watch-page parser returns nil when visitor data is absent")
    func missingVisitorDataReturnsNil() {
        #expect(extractYouTubeVisitorData(from: "<html><body>No config</body></html>") == nil)
    }

    @Test("VisionOS HLS without a VP9 decoder uses its UA and an H.264 master")
    func visionOSHLSClientPolicy() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: false)
        #expect(policy.userAgent == InnerTubeClients.VisionOS.userAgent)
        #expect(policy.filtersMasterManifest)
        #expect(policy.videoCodecs == ["avc1"])
    }

    @Test("VisionOS HLS with a VP9 decoder plays the uncapped VP9 ladder")
    func visionOSVP9Policy() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: true)
        #expect(policy.filtersMasterManifest)
        #expect(policy.videoCodecs == ["vp09"])
        #expect(policy.maximumHeight == nil)
        #expect(policy.cappedHeight(requested: nil) == nil)
        #expect(policy.cappedHeight(requested: 1440) == 1440)
    }

    @Test("codec settings: VP9 needs a decoder, H.264 fills in when VP9 can't play")
    func codecSettings() {
        func codecs(vp9: Bool, h264: Bool, decoder: Bool) -> [String] {
            HLSPlaybackPolicy.resolve(
                label: "VisionOS/HLS", isHLS: true, vp9Enabled: vp9, h264Enabled: h264, vp9Available: decoder
            ).videoCodecs
        }
        #expect(codecs(vp9: true, h264: false, decoder: true) == ["vp09"])
        #expect(codecs(vp9: true, h264: true, decoder: true) == ["vp09", "avc1"])
        #expect(codecs(vp9: false, h264: true, decoder: true) == ["avc1"])
        #expect(codecs(vp9: true, h264: false, decoder: false) == ["avc1"])
        let both = HLSPlaybackPolicy.resolve(
            label: "VisionOS/HLS", isHLS: true, vp9Enabled: true, h264Enabled: true, vp9Available: true)
        #expect(both.maximumHeight == nil)
        let h264Only = HLSPlaybackPolicy.resolve(
            label: "VisionOS/HLS", isHLS: true, vp9Enabled: false, h264Enabled: true, vp9Available: true)
        #expect(h264Only.maximumHeight == 1080)
    }

    @Test("settings default to VP9 on, H.264 off, and survive old settings without the keys")
    func codecSettingsDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.vp9Enabled)
        #expect(!decoded.h264Enabled)
    }

    @Test("picker rows follow the policy's codec filter")
    func pickerFormatsFollowPolicy() {
        let h264 = VideoFormat(
            label: "", width: 1920, height: 1080, fps: 30, mimeType: "video/mp4; codecs=\"avc1.64002A\"")
        let av1 = VideoFormat(
            label: "", width: 3840, height: 2160, fps: 30, mimeType: "video/mp4; codecs=\"av01.0.13M.08\"")
        let vp9 = VideoFormat(label: "", width: 3840, height: 2160, fps: 30, mimeType: "video/webm; codecs=\"vp9\"")
        let all = [h264, av1, vp9]
        let h264Policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: false)
        let vp9Policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: true)
        let plain = HLSPlaybackPolicy.resolve(label: "iOS/HLS", isHLS: true)
        #expect(h264Policy.pickerFormats(from: all, current: [h264, av1]) == [h264])
        #expect(vp9Policy.pickerFormats(from: all, current: [h264, av1]).map(\.height) == [2160])
        #expect(plain.pickerFormats(from: all, current: [h264, av1]) == [h264, av1])
        let both = HLSPlaybackPolicy.resolve(
            label: "VisionOS/HLS", isHLS: true, vp9Enabled: true, h264Enabled: true, vp9Available: true)
        let vp9at1080 = VideoFormat(
            label: "", width: 1920, height: 1080, fps: 30, mimeType: "video/webm; codecs=\"vp9\"")
        let rows = both.pickerFormats(from: all + [vp9at1080], current: [h264, av1])
        #expect(rows.map(\.height) == [2160, 1080, 1080])
        #expect(rows.map(\.codecShortLabel) == ["VP9", "VP9", "H.264"])
        #expect(HLSPlaybackPolicy.videoCodec(ofMimeType: vp9.mimeType) == "vp09")
        #expect(HLSPlaybackPolicy.videoCodec(ofMimeType: h264.mimeType) == "avc1")
    }

    @Test("VP9 picker rows: one per height, highest fps, sorted descending")
    func vp9PickerFormats() {
        let formats = [
            VideoFormat(label: "", width: 1920, height: 1080, fps: 30, mimeType: "video/webm; codecs=\"vp9\""),
            VideoFormat(label: "", width: 1920, height: 1080, fps: 60, mimeType: "video/webm; codecs=\"vp9\""),
            VideoFormat(label: "", width: 3840, height: 2160, fps: 60, mimeType: "video/webm; codecs=\"vp9\""),
            VideoFormat(label: "", width: 3840, height: 2160, fps: 60, mimeType: "video/mp4; codecs=\"av01.0.13M.08\""),
        ]
        let rows = HLSPlaybackPolicy.vp9PickerFormats(formats)
        #expect(rows.map(\.height) == [2160, 1080])
        #expect(rows.last?.fps == 60)
        #expect(rows.allSatisfy { $0.codecShortLabel == "VP9" })
    }

    @Test("VisionOS without VP9 caps Auto and explicit UHD requests at 1080p")
    func visionOSHeightCap() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: false)
        #expect(policy.cappedHeight(requested: nil) == 1080)
        #expect(policy.cappedHeight(requested: 2160) == 1080)
        #expect(policy.cappedHeight(requested: 1440) == 1080)
        #expect(policy.cappedHeight(requested: 720) == 720)
    }

    @Test("VisionOS picker exposes only H.264 formats through 1080p")
    func visionOSPickerCompatibility() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: false)
        let h264 = VideoFormat(
            label: "", width: 1920, height: 1080, fps: 30, mimeType: "video/mp4; codecs=\"avc1.64002A\"")
        let vp9 = VideoFormat(
            label: "", width: 1920, height: 1080, fps: 30, mimeType: "video/mp4; codecs=\"vp09.00.41.08\"")
        let uhd = VideoFormat(
            label: "", width: 3840, height: 2160, fps: 30, mimeType: "video/mp4; codecs=\"avc1.640033\"")
        #expect(policy.pickerFormats(from: [], current: [uhd, h264, vp9]) == [h264])
    }

    @Test("WebSafari HLS retains its browser UA without a height cap")
    func webSafariPolicyUnchanged() {
        let policy = HLSPlaybackPolicy.resolve(label: "WebSafari[1]/HLS", isHLS: true)
        #expect(policy.userAgent == InnerTubeClients.WebSafari.userAgent)
        #expect(policy.maximumHeight == nil)
        #expect(!policy.filtersMasterManifest)
    }

    @Test("filtered master keeps audio while removing VP9 and UHD variants")
    func filtersMasterForTVOS() {
        let manifest = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="English - original",DEFAULT=NO,AUTOSELECT=YES,URI="audio.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.64002A,mp4a.40.2",AUDIO="234"
            h264-1080.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="vp09.00.41.08,mp4a.40.2",AUDIO="234"
            vp9-1080.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=18000000,RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2",AUDIO="234"
            h264-2160.m3u8
            """

        let filtered = filterHLSMasterManifest(
            manifest, maximumHeight: 1080, videoCodecs: ["avc1"]
        )
        #expect(filtered.contains("TYPE=AUDIO"))
        #expect(filtered.contains("DEFAULT=YES"))
        #expect(filtered.contains("h264-1080.m3u8"))
        #expect(!filtered.contains("vp9-1080.m3u8"))
        #expect(!filtered.contains("h264-2160.m3u8"))

        let vp9 = filterHLSMasterManifest(manifest, maximumHeight: nil, videoCodecs: ["vp09"])
        #expect(vp9.contains("TYPE=AUDIO"))
        #expect(vp9.contains("vp9-1080.m3u8"))
        #expect(!vp9.contains("h264-1080.m3u8"))
    }
}
