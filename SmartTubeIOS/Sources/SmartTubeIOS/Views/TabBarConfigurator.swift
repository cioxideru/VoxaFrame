#if os(iOS)
import SwiftUI
import UIKit

// MARK: - TabBarConfigurator (#107, #143, PLAN-0033)
//
// Forces the tab bar to render as an opaque bar instead of iOS 26's Liquid Glass
// material when `AppSettings.disableLiquidGlass` is on.
//
// Apple's documented opt-out (`UIDesignRequiresCompatibility` in Info.plist) is a
// build-time-only key UIKit reads once at process launch — it can't reflect a
// runtime, per-user Settings toggle without shipping a separate build per choice
// (see #143). This instead styles the *actual, already-on-screen* UITabBar instance
// directly (not just the `UITabBar.appearance()` proxy, which only affects tab bars
// created *after* the proxy is set — our tab bar already exists by the time the user
// flips this switch) so the change is visible immediately, no restart needed.
//
// A zero-size UIViewRepresentable is the only reliable way to reach the live
// UITabBar instance from SwiftUI's TabView, which doesn't expose one directly.
struct TabBarConfigurator: UIViewRepresentable {
    let disableLiquidGlass: Bool

    @MainActor
    final class Coordinator {
        weak var configuredController: UITabBarController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        // Leave SwiftUI's update before UIKit calls back into its sidebar visibility binding.
        Task { @MainActor in
            guard let window = uiView.window,
                let controller = window.rootViewController?.tabBarController(in: uiView)
            else { return }
            if coordinator.configuredController !== controller {
                coordinator.configuredController = controller
                if controller.traitCollection.userInterfaceIdiom == .pad {
                    // Apply the initial window shape once; later updates preserve the user's toggle.
                    controller.sidebar.isHidden = window.bounds.width <= window.bounds.height
                }
            }
            let tabBar = controller.tabBar
            let appearance = UITabBarAppearance()
            if disableLiquidGlass {
                appearance.configureWithOpaqueBackground()
            } else {
                appearance.configureWithDefaultBackground()
            }
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
    }
}

extension UIViewController {
    /// Walks the view-controller hierarchy (children, then presented) starting from
    /// `self` looking for a `UITabBarController` — `uiView`'s own `tabBarController`
    /// property is nil since a plain `UIView` injected via a SwiftUI representable
    /// isn't itself managed by the tab bar controller.
    fileprivate func tabBarController(in view: UIView) -> UITabBarController? {
        if let tabBarController = self as? UITabBarController { return tabBarController }
        for child in children {
            if let found = child.tabBarController(in: view) { return found }
        }
        if let presented = presentedViewController { return presented.tabBarController(in: view) }
        return nil
    }
}
#endif
