import Foundation
import os

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Home batch continuation

extension InnerTubeAPI {
    /// Home rows whose cursor falls back to the batch-ending Refresh button when the feed has none of its own.
    ///
    /// The signed-in (TV) Home ends each recommendations batch with a shelf holding only a "Refresh"
    /// `gridButtonRenderer`; its `loadReloadContinuationCommand` loads the next batch through the same browse
    /// continuation, and the section carries no `continuations`. Row continuations
    /// (`horizontalListRenderer.continuations`) only extend one shelf and never become the Home cursor.
    func parseHomeRows(from json: [String: Any]) -> [VideoGroup] {
        var rows = parseVideoGroupRows(from: json)
        guard !rows.isEmpty, !rows.contains(where: { $0.nextPageToken != nil }),
            let token = homeRefreshContinuation(json)
        else { return rows }
        tubeLog.notice("[home] no feed cursor; continuing with the Refresh batch token")
        rows[rows.count - 1].nextPageToken = token
        return rows
    }

    /// Internal accessor so unit tests can exercise the Home row parser without a live network.
    func parseHomeRowsForTesting(_ json: [String: Any]) -> [VideoGroup] {
        parseHomeRows(from: json)
    }

    private func homeRefreshContinuation(_ object: Any, depth: Int = 0) -> String? {
        guard depth < 50 else { return nil }
        if let items = object as? [Any] {
            for item in items {
                if let token = homeRefreshContinuation(item, depth: depth + 1) { return token }
            }
        } else if let dict = object as? [String: Any] {
            if let button = dict["gridButtonRenderer"] as? [String: Any] {
                let endpoint = button["navigationEndpoint"] as? [String: Any]
                let command = endpoint?["loadReloadContinuationCommand"] as? [String: Any]
                return command?["continuation"] as? String
            }
            for key in dict.keys.sorted() where key != "frameworkUpdates" && key != "responseContext" {
                if let value = dict[key], let token = homeRefreshContinuation(value, depth: depth + 1) {
                    return token
                }
            }
        }
        return nil
    }
}
