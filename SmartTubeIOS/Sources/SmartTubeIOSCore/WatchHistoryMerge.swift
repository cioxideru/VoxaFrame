import Foundation

// MARK: - WatchHistoryMerge (PLAN-0053)
//
// Orders the History tab when both the on-device history and the account history are available.
// Since PLAN-0046 YouTube credits VoxaFrame watches to the account, so the account order is the source
// of truth: it also lists videos watched in the official apps, which the device never saw. Account items
// carry no watch dates, so an on-device entry missing from the account list ("local-only": still being
// synced, credited to nobody, or simply beyond the first page) is placed relative to the on-device entries
// the account does list ("anchors"):
// - before the first anchor: at the top when watched within `unsyncedLocalWindow` (YouTube has not listed
//   it yet), otherwise right before that anchor;
// - between two anchors: right after the newer one;
// - after the last anchor, or with no anchor at all (and older than the window): after the account page,
//   where a later account page that lists it drops its duplicate.

enum WatchHistoryMerge {
    /// How long an on-device watch missing from the account history still counts as "not synced yet" and
    /// stays at the top of the History tab.
    static let unsyncedLocalWindow: TimeInterval = 60 * 60

    static func merge(local: [LocalWatchHistoryEntry], remote: [Video], now: Date) -> [Video] {
        guard !remote.isEmpty else { return local.map(\.video) }
        let remoteIds = Set(remote.map(\.id))
        let firstAnchor = local.firstIndex { remoteIds.contains($0.video.id) }
        let lastAnchor = local.lastIndex { remoteIds.contains($0.video.id) }

        var top: [Video] = []
        var beforeFirstAnchor: [Video] = []
        var afterAnchor: [String: [Video]] = [:]
        var trailing: [Video] = []
        var newerAnchorId: String?
        for (index, entry) in local.enumerated() {
            let id = entry.video.id
            if remoteIds.contains(id) {
                newerAnchorId = id
            } else if let anchorId = newerAnchorId {
                if let lastAnchor, index < lastAnchor {
                    afterAnchor[anchorId, default: []].append(entry.video)
                } else {
                    trailing.append(entry.video)
                }
            } else if now.timeIntervalSince(entry.watchedAt) <= unsyncedLocalWindow {
                top.append(entry.video)
            } else if firstAnchor != nil {
                beforeFirstAnchor.append(entry.video)
            } else {
                trailing.append(entry.video)
            }
        }

        let firstAnchorId = firstAnchor.map { local[$0].video.id }
        var merged = top
        for video in remote {
            if video.id == firstAnchorId { merged += beforeFirstAnchor }
            merged.append(video)
            merged += afterAnchor[video.id] ?? []
        }
        merged += trailing
        var seen = Set<String>()
        return merged.filter { seen.insert($0.id).inserted }
    }
}
