#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// Window presentation belongs to the shell; changing it never moves or replaces the player view.
@MainActor @Observable
final class MacWindowState: NSObject {
    private(set) var isFullScreen = false
    private(set) var inspectorFits = true
    private(set) var sidebarFits = true
    private(set) var activePlayer: ObjectIdentifier?
    private var windowedSidebarVisibility = NavigationSplitViewVisibility.automatic
    @ObservationIgnored private var sidebarBeforeAutoCollapse: NavigationSplitViewVisibility?
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private var savedToolbarVisibility: Bool?
    @ObservationIgnored private var isClosing = false

    var isImmersive: Bool { isFullScreen && activePlayer != nil }
    var allowsInspector: Bool { !isImmersive && inspectorFits }

    var sidebarVisibility: NavigationSplitViewVisibility {
        get { isImmersive ? .detailOnly : windowedSidebarVisibility }
        set {
            // Ignore SwiftUI echoing our collapse, but accept an explicit change even in a narrow window.
            guard !isImmersive, newValue != windowedSidebarVisibility else { return }
            sidebarBeforeAutoCollapse = nil
            windowedSidebarVisibility = newValue
        }
    }

    var fullScreenTitle: String {
        isFullScreen
            ? String(localized: "Exit Full Screen", bundle: .module)
            : String(localized: "Enter Full Screen", bundle: .module)
    }

    func setPlayer(_ player: ObjectIdentifier, visible: Bool) {
        if visible {
            activePlayer = player
        } else if activePlayer == player {
            activePlayer = nil
        }
        synchronizeToolbar()
    }

    func toggleFullScreen() {
        guard let window, window.attachedSheet == nil else { return }
        window.toggleFullScreen(nil)
    }

    func exitFullScreen() {
        if isFullScreen { toggleFullScreen() }
    }

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        isClosing = true
        restoreToolbar()
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: nil, object: oldWindow)
        }
        NotificationCenter.default.removeObserver(self, name: NSApplication.willTerminateNotification, object: nil)
        self.window = window
        isClosing = false
        guard let window else { return }
        window.contentMinSize = VFMacWindow.minimumSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        if !window.styleMask.contains(.fullScreen), let size = window.contentView?.frame.size,
            size.width < VFMacWindow.minimumSize.width || size.height < VFMacWindow.minimumSize.height
        {
            window.setContentSize(
                CGSize(
                    width: max(size.width, VFMacWindow.minimumSize.width),
                    height: max(size.height, VFMacWindow.minimumSize.height)))
        }
        for name in [
            NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
            NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
            NSWindow.didResizeNotification,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowChanged(_:)), name: name, object: window)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(restoreToolbarBeforeClosing), name: NSWindow.willCloseNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(restoreToolbarBeforeClosing), name: NSApplication.willTerminateNotification,
            object: nil)
        updateLayout(width: window.contentLayoutRect.width, isFullScreen: window.styleMask.contains(.fullScreen))
    }

    /// Kept separate from AppKit notifications so resize/full-screen restoration can be tested without a Space switch.
    func updateLayout(width: CGFloat, isFullScreen: Bool) {
        if self.isFullScreen != isFullScreen { self.isFullScreen = isFullScreen }
        let inspectorFits = width >= VFMacWindow.inspectorCollapseWidth
        if self.inspectorFits != inspectorFits { self.inspectorFits = inspectorFits }
        let sidebarFits = width >= VFMacWindow.sidebarCollapseWidth
        if self.sidebarFits != sidebarFits {
            self.sidebarFits = sidebarFits
            if sidebarFits {
                if let sidebarBeforeAutoCollapse { windowedSidebarVisibility = sidebarBeforeAutoCollapse }
                sidebarBeforeAutoCollapse = nil
            } else {
                sidebarBeforeAutoCollapse = windowedSidebarVisibility
                windowedSidebarVisibility = .detailOnly
            }
        }
        synchronizeToolbar()
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard let window else { return }
        let fullScreen: Bool
        switch notification.name {
        case NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification:
            fullScreen = true
        case NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification:
            fullScreen = false
        default:
            // Resize notifications during the animation must retain the will-enter/will-exit state.
            fullScreen = isFullScreen
        }
        updateLayout(width: window.contentLayoutRect.width, isFullScreen: fullScreen)
    }

    @objc private func windowResignedKey() {
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    @objc private func restoreToolbarBeforeClosing() {
        isClosing = true
        restoreToolbar()
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func synchronizeToolbar() {
        guard !isClosing else { return }
        if isImmersive, let toolbar = window?.toolbar {
            if savedToolbarVisibility == nil { savedToolbarVisibility = toolbar.isVisible }
            if toolbar.isVisible { toolbar.isVisible = false }
        } else {
            restoreToolbar()
        }
    }

    private func restoreToolbar() {
        if let savedToolbarVisibility {
            self.savedToolbarVisibility = nil
            if let toolbar = window?.toolbar, toolbar.isVisible != savedToolbarVisibility {
                toolbar.isVisible = savedToolbarVisibility
            }
        }
    }
}

/// Finds this scene's window without replacing SwiftUI's window delegate or using the application's key window.
struct MacWindowAttachment: NSViewRepresentable {
    let state: MacWindowState

    func makeNSView(context: Context) -> WindowView { WindowView(state: state) }
    func updateNSView(_ nsView: WindowView, context: Context) {}

    static func dismantleNSView(_ nsView: WindowView, coordinator: ()) {
        nsView.state.attach(to: nil)
    }

    final class WindowView: NSView {
        let state: MacWindowState

        init(state: MacWindowState) {
            self.state = state
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Attaching publishes layout state; defer it until SwiftUI has finished mounting this view.
            Task { @MainActor [weak self] in
                guard let self else { return }
                state.attach(to: window)
            }
        }
    }
}
#endif
