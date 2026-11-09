import Foundation
import os

// MARK: - ActiveChannel
//
// The Brand Account the signed-in user selected. Process-wide rather than set per instance like
// `setAuthToken`: many InnerTubeAPI instances exist, and one that missed the change would silently
// act as the wrong channel. InnerTubeAPI reads it while building each authenticated request.

public final class ActiveChannel: Sendable {
    public static let shared = ActiveChannel()

    static let headerField = "X-Goog-Pageid"

    private let state = OSAllocatedUnfairLock<String?>(initialState: nil)

    public init() {}

    /// nil = the primary account (no header).
    public var pageId: String? { state.withLock { $0 } }

    public func set(pageId: String?) {
        state.withLock { $0 = pageId }
    }

    /// Adds `X-Goog-Pageid` when a Brand Account is selected. Call only on requests that carry the
    /// account's authorization (Bearer or SAPISIDHASH); the OAuth token stays the primary account's.
    public func apply(to request: inout URLRequest) {
        guard let pageId else { return }
        request.setValue(pageId, forHTTPHeaderField: Self.headerField)
    }
}
