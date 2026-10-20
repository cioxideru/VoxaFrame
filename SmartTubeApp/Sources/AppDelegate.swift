import Foundation
import SmartTubeIOSCore

#if os(iOS)
import UIKit
import OSLog
import SmartTubeIOS

private let appDelegateLog = Logger(subsystem: "com.void.smarttube.app", category: "AppDelegate")

/// Provides the per-screen orientation mask that UIKit queries on every
/// orientation-change event. Returns `.allButUpsideDown` so that
/// `UIWindowScene.requestGeometryUpdate` can successfully request landscape
/// when the player opens and portrait when it closes. Proactive
/// portrait↔landscape transitions are managed by `OrientationManager`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    override init() {
        super.init()
        #if DEBUG
        // Hardware calibration avoids XCTest waiting for system-control animation completion.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        OfflineCoordinator.shared.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Return .allButUpsideDown at all times so that:
        // 1. UIKit's intersection with the view controller hierarchy does not
        //    restrict to portrait-only while the full-screen player cover is
        //    being presented (PresentationHostingController caches the supported
        //    mask at creation time, before PlayerView.onAppear fires).
        // 2. OrientationManager.requestGeometryUpdate can successfully request
        //    landscape when the player opens and portrait when it closes.
        // Proactive portrait↔landscape transitions are still managed by
        // OrientationManager via UIWindowScene.requestGeometryUpdate.
        let mask = UIInterfaceOrientationMask.allButUpsideDown
        appDelegateLog.notice(
            "[AppDelegate] supportedInterfaceOrientationsFor — returning mask=\(mask.rawValue) playerIsActive=\(OrientationManager.shared.playerIsActive)"
        )
        return mask
    }
}
#endif

extension AppEntry {
    // MARK: - Stub data for UI testing

    /// Resolves the `[Video]` list used when launched with `--uitesting-shorts`.
    ///
    /// If the launch argument `--uitesting-shorts-ids=ID1,ID2,ID3` is present the
    /// returned videos use those real YouTube Short video IDs, allowing tests that
    /// verify actual playback (e.g. no error banner) to load real streams without
    /// navigating through the full app.
    ///
    /// If no custom IDs are provided the default `stubShorts` (fake IDs) are used,
    /// which is fine for tests that only exercise player UI (index label, swipes,
    /// controls overlay) and don't care about real video loading.
    static func shortsForUITesting() -> [Video] {
        let args = ProcessInfo.processInfo.arguments
        guard let idsArg = args.first(where: { $0.hasPrefix("--uitesting-shorts-ids=") }) else {
            return stubShorts
        }
        let raw = String(idsArg.dropFirst("--uitesting-shorts-ids=".count))
        let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return stubShorts }
        return ids.enumerated().map { idx, id in
            Video(
                id: id, title: "Short \(idx + 1)", channelTitle: "Test Channel",
                channelId: "UCBcRF18a7Qf58cCRy5xuWwQ", isShort: true)
        }
    }

    static let stubShorts: [Video] = [
        Video(id: "short-1", title: "Short One", channelTitle: "Channel A", isShort: true),
        Video(id: "short-2", title: "Short Two", channelTitle: "Channel B", isShort: true),
        Video(id: "short-3", title: "Short Three", channelTitle: "Channel C", isShort: true),
    ]
}
