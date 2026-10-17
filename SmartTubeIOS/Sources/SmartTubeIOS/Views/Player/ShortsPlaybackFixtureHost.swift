#if DEBUG && os(iOS)
import SmartTubeIOSCore
import SwiftUI

/// Test-only presentation boundary so UI tests exercise actual dismissal and a fresh session.
public struct ShortsPlaybackFixtureHost: View {
    let videos: [Video]
    let api: InnerTubeAPI
    @State private var isPresented = true

    public init(videos: [Video], api: InnerTubeAPI) {
        self.videos = videos
        self.api = api
    }

    public var body: some View {
        Button("Open Shorts") { isPresented = true }
            .accessibilityIdentifier(AccessibilityID.shortsReopenTestButton)
            .fullScreenCover(isPresented: $isPresented) {
                ShortsPlayerView(videos: videos, api: api)
            }
    }
}
#endif
