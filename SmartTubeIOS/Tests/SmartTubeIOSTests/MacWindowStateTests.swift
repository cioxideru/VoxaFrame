#if os(macOS)
import AppKit
import Observation
import SwiftUI
import Testing

@testable import SmartTubeIOS

@Suite("Mac window presentation — PLAN-0029", .serialized)
@MainActor
struct MacWindowStateTests {
    // Identity only: these tests don't construct a player or make any network requests.
    private final class PlayerIdentity {}

    @Test func inspectorAndSidebarHaveIndependentCollapseWidths() {
        let state = MacWindowState()
        state.sidebarVisibility = .all
        state.updateLayout(width: 1000, isFullScreen: false)
        #expect(state.allowsInspector)
        #expect(state.sidebarVisibility == .all)

        state.updateLayout(width: 999, isFullScreen: false)
        #expect(!state.allowsInspector)
        #expect(state.sidebarVisibility == .all)

        state.updateLayout(width: 800, isFullScreen: false)
        #expect(state.sidebarFits)
        state.updateLayout(width: 799, isFullScreen: false)
        #expect(!state.sidebarFits)
        #expect(state.sidebarVisibility == .detailOnly)
    }

    @Test func automaticCollapsePreservesWindowedSidebarChoice() {
        let state = MacWindowState()
        state.sidebarVisibility = .all
        state.updateLayout(width: VFMacWindow.minimumSize.width, isFullScreen: false)
        state.sidebarVisibility = .detailOnly  // SwiftUI reporting the forced collapse.
        state.updateLayout(width: 1280, isFullScreen: false)
        #expect(state.sidebarVisibility == .all)

        state.sidebarVisibility = .detailOnly  // An explicit user choice in a wide window.
        state.updateLayout(width: 720, isFullScreen: false)
        state.updateLayout(width: 1280, isFullScreen: false)
        #expect(state.sidebarVisibility == .detailOnly)
    }

    @Test func narrowWindowAcceptsSidebarCommandsUntilTheNextThresholdCrossing() {
        let state = MacWindowState()
        state.sidebarVisibility = .all
        state.updateLayout(width: 799, isFullScreen: false)
        #expect(state.sidebarVisibility == .detailOnly)

        state.sidebarVisibility = .all  // View > Show Sidebar, even below the collapse width.
        state.updateLayout(width: 750, isFullScreen: false)
        #expect(state.sidebarVisibility == .all)
        state.sidebarVisibility = .detailOnly
        state.updateLayout(width: 1280, isFullScreen: false)
        #expect(state.sidebarVisibility == .detailOnly)

        state.sidebarVisibility = .all
        state.updateLayout(width: 799, isFullScreen: false)
        #expect(state.sidebarVisibility == .detailOnly)
    }

    @Test func resizingWithinTheSameThresholdsDoesNotPublishLayoutChanges() {
        let state = MacWindowState()
        state.updateLayout(width: 1280, isFullScreen: false)
        withObservationTracking {
            _ = state.inspectorFits
            _ = state.sidebarFits
            _ = state.isFullScreen
            _ = state.sidebarVisibility
        } onChange: {
            Issue.record("A resize within the same thresholds invalidated the window layout")
        }

        for width in [CGFloat(1200), 1100, 1000] {
            state.updateLayout(width: width, isFullScreen: false)
        }
    }

    @Test func fullScreenRestoresPanelsAtTheWindowedWidth() {
        let state = MacWindowState()
        let player = PlayerIdentity()
        state.sidebarVisibility = .all
        state.setPlayer(ObjectIdentifier(player), visible: true)
        state.updateLayout(width: 1920, isFullScreen: true)
        #expect(state.isImmersive)
        #expect(!state.allowsInspector)
        #expect(state.sidebarVisibility == .detailOnly)
        state.sidebarVisibility = .detailOnly

        state.updateLayout(width: 900, isFullScreen: false)
        #expect(!state.isImmersive)
        #expect(!state.allowsInspector)
        #expect(state.sidebarVisibility == .all)
        state.updateLayout(width: 1280, isFullScreen: false)
        #expect(state.allowsInspector)
    }

    @Test func fullScreenPreservesAnExplicitlyHiddenSidebar() {
        let state = MacWindowState()
        let player = PlayerIdentity()
        state.sidebarVisibility = .detailOnly
        state.setPlayer(ObjectIdentifier(player), visible: true)
        for _ in 0..<3 {
            state.updateLayout(width: 1920, isFullScreen: true)
            state.updateLayout(width: 1280, isFullScreen: false)
            #expect(state.sidebarVisibility == .detailOnly)
        }
    }

    @Test func departingPlayerCannotClearItsReplacement() {
        let state = MacWindowState()
        let previous = PlayerIdentity()
        let current = PlayerIdentity()
        state.updateLayout(width: 1920, isFullScreen: true)
        #expect(!state.isImmersive)  // Ordinary browsing in a full-screen window.
        state.setPlayer(ObjectIdentifier(previous), visible: true)
        state.setPlayer(ObjectIdentifier(current), visible: true)
        state.setPlayer(ObjectIdentifier(previous), visible: false)
        #expect(state.isImmersive)
        #expect(state.activePlayer == ObjectIdentifier(current))
        state.setPlayer(ObjectIdentifier(current), visible: false)
        #expect(!state.isImmersive)
        #expect(state.allowsInspector)
    }

    @Test func panelsFollowWillNotificationsBeforeTheFullScreenAnimation() {
        let state = MacWindowState()
        let window = makeWindow(toolbarVisible: true)
        let player = PlayerIdentity()
        state.attach(to: window)
        defer { state.attach(to: nil) }
        state.sidebarVisibility = .all
        state.setPlayer(ObjectIdentifier(player), visible: true)

        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        #expect(state.isImmersive)
        #expect(!state.allowsInspector)
        #expect(state.sidebarVisibility == .detailOnly)
        #expect(window.toolbar?.isVisible == false)

        // AppKit can resize before its fullScreen style bit changes.
        #expect(!window.styleMask.contains(.fullScreen))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        #expect(state.isImmersive)

        NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
        #expect(!state.isImmersive)
        #expect(state.allowsInspector)
        #expect(state.sidebarVisibility == .all)
        #expect(window.toolbar?.isVisible == true)
    }

    @Test(arguments: [true, false])
    func fullScreenPreservesToolbarVisibility(wasVisible: Bool) {
        let state = MacWindowState()
        let window = makeWindow(toolbarVisible: wasVisible)
        let player = PlayerIdentity()
        state.attach(to: window)
        defer { state.attach(to: nil) }
        state.setPlayer(ObjectIdentifier(player), visible: true)
        state.updateLayout(width: 1920, isFullScreen: true)
        #expect(window.toolbar?.isVisible == false)
        state.updateLayout(width: 1280, isFullScreen: false)
        #expect(window.toolbar?.isVisible == wasVisible)
    }

    @Test(
        arguments: [true, false],
        [NSWindow.willCloseNotification, NSApplication.willTerminateNotification]
    )
    func closingDuringFullScreenRestoresToolbar(wasVisible: Bool, notification: Notification.Name) {
        let state = MacWindowState()
        let window = makeWindow(toolbarVisible: wasVisible)
        let player = PlayerIdentity()
        state.attach(to: window)
        defer { state.attach(to: nil) }
        state.setPlayer(ObjectIdentifier(player), visible: true)
        state.updateLayout(width: 1920, isFullScreen: true)
        #expect(window.toolbar?.isVisible == false)

        NotificationCenter.default.post(
            name: notification, object: notification == NSWindow.willCloseNotification ? window : nil)
        #expect(window.toolbar?.isVisible == wasVisible)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        #expect(window.toolbar?.isVisible == wasVisible)
    }

    private func makeWindow(toolbarVisible: Bool) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.toolbar = NSToolbar(identifier: "MacWindowStateTests")
        window.toolbar?.isVisible = toolbarVisible
        return window
    }
}
#endif
