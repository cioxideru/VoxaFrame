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

    @Test("VisionOS HLS uses its matching UA and preserves the master")
    func visionOSHLSClientPolicy() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        #expect(policy.userAgent == InnerTubeClients.VisionOS.userAgent)
        #expect(policy.filtersMasterManifest)
        #expect(policy.requiresH264)
    }

    @Test("VisionOS caps Auto and explicit UHD requests at 1080p")
    func visionOSHeightCap() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        #expect(policy.cappedHeight(requested: nil) == 1080)
        #expect(policy.cappedHeight(requested: 2160) == 1080)
        #expect(policy.cappedHeight(requested: 1440) == 1080)
        #expect(policy.cappedHeight(requested: 720) == 720)
    }

    @Test("VisionOS picker exposes only H.264 formats through 1080p")
    func visionOSPickerCompatibility() {
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true)
        #expect(
            policy.allowsFormat(
                height: 1080, mimeType: "video/mp4; codecs=\"avc1.64002A\""
            ))
        #expect(
            !policy.allowsFormat(
                height: 1080, mimeType: "video/mp4; codecs=\"vp09.00.41.08\""
            ))
        #expect(
            !policy.allowsFormat(
                height: 2160, mimeType: "video/mp4; codecs=\"avc1.640033\""
            ))
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
            manifest, maximumHeight: 1080, requiredVideoCodec: "avc1"
        )
        #expect(filtered.contains("TYPE=AUDIO"))
        #expect(filtered.contains("DEFAULT=YES"))
        #expect(filtered.contains("h264-1080.m3u8"))
        #expect(!filtered.contains("vp9-1080.m3u8"))
        #expect(!filtered.contains("h264-2160.m3u8"))
    }
}
