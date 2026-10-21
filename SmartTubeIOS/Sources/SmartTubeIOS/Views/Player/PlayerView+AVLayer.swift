import AVFoundation
import AVKit
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Platform-specific AVKit / UIKit views
//
// Extracted from PlayerView.swift to keep that file under 1 000 lines.

// MARK: - PersistentPlayerLayerView (iOS)

#if os(iOS)
/// Only the current presentation may move the shared layer. A retained, offscreen
/// container must not steal it during UIKit/SwiftUI transition updates.
struct PersistentPlayerLayerView: UIViewRepresentable {
    @Environment(PlayerStateStore.self) private var playerState
    let presentation: PlayerStateStore.Presentation
    var videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.backgroundColor = .black
        container.isAccessibilityElement = false
        container.accessibilityElementsHidden = true
        return container
    }

    func updateUIView(_ container: Container, context: Context) {
        let state = playerState
        container.attach = { [weak state, weak container] in
            guard let state, let container,
                state.presentation == presentation, container.window != nil
            else { return }
            let host = state.playerHostView
            if host.superview !== container {
                host.translatesAutoresizingMaskIntoConstraints = true
                host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(host)
            }
            host.frame = container.bounds
            host.videoGravity = videoGravity
        }
        container.attach?()
    }

    final class Container: UIView {
        var attach: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach?()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attach?()
        }
    }
}
#endif

// MARK: - AVPlayerLayerView

#if os(iOS) || os(tvOS)
/// Lightweight UIViewRepresentable wrapping an `AVPlayerLayer` directly.
/// Unlike `VideoPlayer` / `AVPlayerViewController`, it does not interfere
/// with the UIKit accessibility tree so SwiftUI overlays remain reachable.
/// On tvOS, `AVPlayerViewController` would provide system transport controls
/// but `AVPlayerLayer` is used here for layout consistency with iOS.
/// Named `PlayerAVLayerView` to avoid a module-level name clash with
/// `ShortsPlayerView`, which uses this type via `videoGravity: .resizeAspectFill`.
struct PlayerAVLayerView: UIViewRepresentable {
    let player: AVPlayer?
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onLayerReady: ((AVPlayerLayer) -> Void)? = nil

    func makeUIView(context: Context) -> _PlayerUIView {
        let view = _PlayerUIView()
        view.backgroundColor = .black
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.onLayerReady = onLayerReady
        return view
    }

    func updateUIView(_ uiView: _PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
        uiView.playerLayer.videoGravity = videoGravity
    }

    final class _PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            guard let playerLayer = layer as? AVPlayerLayer else {
                fatalError("layerClass must create an AVPlayerLayer")
            }
            return playerLayer
        }
        var onLayerReady: ((AVPlayerLayer) -> Void)?
        private var didFireCallback = false

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            guard newWindow != nil, !didFireCallback else { return }
            didFireCallback = true
            // Defer to next run-loop tick so the layer has a non-zero frame.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onLayerReady?(self.playerLayer)
            }
        }
    }
}

// MARK: - PiPDelegate

/// AVPictureInPictureControllerDelegate that notifies a SwiftUI closure when
/// PiP starts or stops, and implements the restore callback required for a
/// smooth transition back to full-screen without rebuffering.
final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private let onWillStart: () -> Void
    private let onActiveChange: (Bool) -> Void
    private let onRestore: (@escaping (Bool) -> Void) -> Void

    init(
        onWillStart: @escaping () -> Void, onActiveChange: @escaping (Bool) -> Void,
        onRestore: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        self.onWillStart = onWillStart
        self.onActiveChange = onActiveChange
        self.onRestore = onRestore
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onWillStart()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onActiveChange(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onActiveChange(false)
    }

    /// Called when the user taps the PiP window to return to the app.
    /// Must call completionHandler(true) once the UI is ready to show the video
    /// again — without this iOS cannot complete the restore animation and the
    /// player rebuffers/stutters.
    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        onRestore(completionHandler)
    }
}

// MARK: - HoldSpeedBadge

struct HoldSpeedBadge: View {
    var body: some View {
        VStack(spacing: VFSpace.s4) {
            Image(systemName: AppSymbol.skipForward)
                .font(.title3.weight(.semibold))
            Text(verbatim: "2×")  // verbatim: a rate, written the same in every language
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
        }
        .foregroundStyle(VFColor.onMedia)
        .padding(.horizontal, VFSpace.s16)
        .padding(.vertical, VFSpace.s8)
        .background(VFColor.scrim, in: RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityIdentifier(AccessibilityID.playerHoldSpeedBadge)
    }
}

#endif  // os(iOS) || os(tvOS)

// MARK: - PlayerNSLayerView (macOS)

#if os(macOS)
/// NSViewRepresentable wrapping an AVPlayerLayer directly — the AppKit
/// equivalent of PlayerAVLayerView on iOS/tvOS.
struct PlayerNSLayerView: NSViewRepresentable {
    let player: AVPlayer?
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> _PlayerNSView {
        let view = _PlayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateNSView(_ nsView: _PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
        nsView.playerLayer.videoGravity = videoGravity
    }

    final class _PlayerNSView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}
#endif
