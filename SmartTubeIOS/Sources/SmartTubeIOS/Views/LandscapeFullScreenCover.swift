#if os(iOS)
import SwiftUI
import UIKit
import SmartTubeIOSCore
import OSLog

private let landscapeLog = Logger(subsystem: "com.void.smarttube.app", category: "Orientation")

// MARK: - FullScreenPlayerDismissible

/// Conformed to by PlayerStateStore, letting LandscapePresenter wire up its
/// imperative-dismiss hook without referencing the concrete store type.
///
/// `dismissPlayerAction` is set by LandscapePresenter's coordinator when this store's
/// full-screen player is presented, and fired by minimize()/stop() to bypass the
/// SwiftUI update-propagation pause that occurs when the presenting VC's view is
/// removed from the window by UIKit's .fullScreen presentation style (so
/// updateUIViewController never fires while the cover is on screen).
@MainActor
protocol FullScreenPlayerDismissible: AnyObject {
    var dismissPlayerAction: (() -> Void)? { get set }
}

extension PlayerStateStore: FullScreenPlayerDismissible {}

// MARK: - LandscapeAwareHostingController

/// UIHostingController whose supportedInterfaceOrientations returns .allButUpsideDown
/// while OrientationManager.shared.playerIsActive is true. This replaces SwiftUI's
/// internal PresentationHostingController (which hard-locks to portrait) so that UIKit
/// accepts requestGeometryUpdate(.landscape) and honours physical device rotations
/// while the player is on screen.
final class LandscapeAwareHostingController: UIHostingController<AnyView> {
    var onDismiss: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        OrientationManager.shared.playerIsActive ? .allButUpsideDown : .portrait
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            landscapeLog.notice(
                "[LandscapeAwareHostingController] viewDidDisappear isBeingDismissed=true — calling onDismiss")
            onDismiss?()
        }
    }
}

// MARK: - landscapePlayerCover modifier

extension View {
    /// Drop-in replacement for `.fullScreenCover(item:content:)` when presenting
    /// PlayerView on iOS. Hosts the content in a `LandscapeAwareHostingController`
    /// so UIKit can rotate the window to landscape while the player is active.
    func landscapePlayerCover<Item: Identifiable & Hashable, Content: View>(
        item: Binding<Item?>,
        dismissStore: any FullScreenPlayerDismissible,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.background(
            LandscapePresenter(item: item, dismissStore: dismissStore, content: { AnyView(content($0)) })
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

// MARK: - LandscapePresenter (UIViewControllerRepresentable)

private struct LandscapePresenter<Item: Identifiable & Hashable>: UIViewControllerRepresentable {
    @Binding var item: Item?
    /// The presentation store for THIS cover. Wired up imperatively below so
    /// minimize()/stop() can dismiss the hosted VC directly — see
    /// FullScreenPlayerDismissible's doc comment.
    let dismissStore: any FullScreenPlayerDismissible
    let content: (Item) -> AnyView

    // Capture the env objects that PlayerView (and anything it hosts) needs.
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var authService
    @Environment(PlayerStateStore.self) private var playerState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.latestItem = item
        coordinator.capturedPlayerState = playerState
        coordinator.capturedDismissStore = dismissStore
        // Wrap the content with the environment objects so the new UIHostingController
        // root gets the same env as the parent SwiftUI tree.
        let capturedStore = store
        let capturedAuth = authService
        let capturedPlayerState = playerState
        coordinator.contentBuilder = { [content] item in
            AnyView(
                content(item)
                    .environment(capturedStore)
                    .environment(capturedAuth)
                    .environment(capturedPlayerState)
            )
        }
        coordinator.latestBinding = _item

        // Defer UIKit presentation to the next run-loop tick to avoid calling
        // UIKit presentation APIs during a SwiftUI layout/update pass.
        // Capture the generation so stale tasks queued before an onDismiss are no-ops.
        let capturedGen = coordinator.presentationGeneration
        Task { @MainActor in
            guard coordinator.presentationGeneration == capturedGen else { return }
            // Dismiss path: sync() doesn't use `root` when latestItem is nil — the dismiss
            // is done via the stored hostedVC reference. Skip the window guard here because
            // UIKit removes the presenting VC's view from the window during a .fullScreen
            // presentation, making vc.view.window nil while the player is on screen.
            if coordinator.latestItem == nil {
                landscapeLog.notice(
                    "[LandscapePresenter] updateUIViewController — item nil, calling sync for dismiss (bypassing window guard)"
                )
                coordinator.sync(root: UIViewController())
                return
            }
            guard let window = vc.view.window,
                let root = window.rootViewController
            else {
                landscapeLog.notice(
                    "[LandscapePresenter] updateUIViewController — item non-nil but vc.view.window is nil, skipping sync"
                )
                return
            }
            coordinator.sync(root: root)
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        var latestItem: Item?
        var contentBuilder: ((Item) -> AnyView)?
        var latestBinding: Binding<Item?>?
        var capturedPlayerState: PlayerStateStore?
        var capturedDismissStore: (any FullScreenPlayerDismissible)?
        var hostedVC: LandscapeAwareHostingController?
        var presentedID: AnyHashable?
        var isTransitioning = false
        /// Incremented on dismiss; Tasks capture the value at creation and abort if it changed.
        var presentationGeneration = 0
        func sync(root: UIViewController) {
            guard !isTransitioning else { return }
            // Read the live binding: UIKit can hide the presenter before SwiftUI updates it.
            latestItem = latestBinding?.wrappedValue
            guard let currentItem = latestItem else {
                if let hc = hostedVC { dismiss(hc, root: root) }
                return
            }
            guard presentedID != AnyHashable(currentItem.id), let contentBuilder else { return }
            if let hc = hostedVC {
                dismiss(hc, root: root)
                return
            }
            var top = root
            while let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            guard top.view.window != nil, !top.isBeingDismissed,
                top.presentedViewController == nil
            else { return }

            let hc = LandscapeAwareHostingController(rootView: contentBuilder(currentItem))
            hc.modalPresentationStyle = .fullScreen
            hc.view.backgroundColor = .black
            hc.onDismiss = { [weak self, weak hc] in
                guard let self, let hc, self.hostedVC === hc else { return }
                self.presentationGeneration += 1
                self.clearPresentation()
                self.latestBinding?.wrappedValue = nil
            }
            hostedVC = hc
            presentedID = AnyHashable(currentItem.id)
            capturedDismissStore?.dismissPlayerAction = { [weak self, weak hc, weak root] in
                guard let self, let hc, let root else { return }
                self.dismiss(hc, root: root)
            }
            isTransitioning = true
            top.present(hc, animated: false) { [weak self, weak hc] in
                guard let self, let hc, self.hostedVC === hc else { return }
                self.isTransitioning = false
                hc.view.layoutIfNeeded()
                self.capturedPlayerState?.completePictureInPictureRestoration()
                self.sync(root: root)
            }
        }

        private func dismiss(_ hc: LandscapeAwareHostingController, root: UIViewController) {
            guard hostedVC === hc, !hc.isBeingDismissed else { return }
            // Programmatic dismissal must not clear a newer expand/PiP restore request.
            let presentingRoot = hc.view.window?.rootViewController ?? root
            hc.onDismiss = nil
            isTransitioning = true
            hc.dismiss(animated: false) { [weak self] in
                guard let self, self.hostedVC === hc else { return }
                self.clearPresentation()
                self.sync(root: presentingRoot)
            }
        }

        private func clearPresentation() {
            capturedDismissStore?.dismissPlayerAction = nil
            hostedVC = nil
            presentedID = nil
            isTransitioning = false
        }
    }
}
#endif
