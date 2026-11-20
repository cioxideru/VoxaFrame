import Foundation
import SmartTubeIOSCore

// MARK: - Channels (Brand Accounts)
//
// The OAuth token always belongs to the primary Google account. A Brand Account is selected per
// request with `X-Goog-Pageid` (see ActiveChannel), as SmartTube Android does, so switching needs
// no new sign-in.

extension AuthService {

    public var activeChannel: YouTubeChannel? {
        channels.first { $0.pageId == activePageId }
    }

    /// Switches every authenticated request to `channel`, as a new session (`startChannelSession`).
    public func selectChannel(_ channel: YouTubeChannel) {
        guard isSignedIn, channel.pageId != activePageId else { return }
        authLog.notice("selectChannel() — \(channel.isPrimary ? "primary" : "brand account")")
        setActivePageId(channel.pageId)
        accountName = channel.name
        accountAvatarURL = channel.avatarURL
        saveToKeychain()
        startChannelSession()
    }

    /// A new identity is a new session: feeds, channel pages and subscription state reload, an open
    /// Shorts feed closes, and account-bound player data is dropped so watch time is credited to the
    /// selected channel.
    private func startChannelSession() {
        sessionGeneration += 1
        let evict = evictAccountPlayerData
        Task { await evict() }
        notificationCenter.post(name: .activeChannelDidChange, object: nil)
    }

    /// accounts_list is fetched at sign-in only, so the list is empty after a relaunch.
    public func loadChannelsIfNeeded() async {
        guard isSignedIn, channels.isEmpty else { return }
        do { try await fetchUserInfo() } catch {
            authLog.error("loadChannelsIfNeeded() failed: \(ViewModelLogger.errorSummary(error))")
        }
    }

    /// Applies the accounts_list result; a stored channel the account no longer has falls back to
    /// the primary account, as a new session like a switch (PLAN-0052).
    func applyChannels(_ list: [YouTubeChannel]) {
        guard !list.isEmpty else { return }
        channels = list
        if let pageId = activePageId, !list.contains(where: { $0.pageId == pageId }) {
            authLog.notice("applyChannels() — stored Brand Account not found, back to primary")
            setActivePageId(nil)
            startChannelSession()
        }
    }

    func setActivePageId(_ pageId: String?) {
        activePageId = pageId
        activeChannelState.set(pageId: pageId)
        Task { await tokenManager.setPageId(pageId) }
    }

    /// Sign-out: the next account starts on its primary channel.
    func resetChannels() {
        channels = []
        activePageId = nil
        activeChannelState.set(pageId: nil)
    }
}
