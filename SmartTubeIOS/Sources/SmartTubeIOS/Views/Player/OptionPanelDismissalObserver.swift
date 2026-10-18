#if os(iOS)
import SwiftUI
import UIKit

/// SwiftUI's popover has no onDismiss; use UIKit's completed disappearance, not content.onDisappear.
struct OptionPanelDismissalObserver: UIViewControllerRepresentable {
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onDismiss = onDismiss
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onDismiss = onDismiss
    }

    final class Controller: UIViewController {
        var onDismiss: (() -> Void)?

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // Let UIKit finish removing the presented controller before another presentation starts.
            Task { @MainActor [onDismiss] in
                onDismiss?()
            }
        }
    }
}
#endif
