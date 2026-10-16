#if os(iOS)
import AVKit

extension PlayerStateStore {
    /// PiP and its delegate must outlive the fullscreen view that PiP dismisses.
    func configurePiP(enabled: Bool) {
        guard enabled else {
            pipController?.stopPictureInPicture()
            pipController = nil
            pipDelegate = nil
            pictureInPictureChanged(active: false)
            return
        }
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting-enable-pip")
        guard vm.isPlaying, pipController == nil,
            testing || AVPictureInPictureController.isPictureInPictureSupported()
        else { return }
        let controller = AVPictureInPictureController(playerLayer: playerHostView.playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        let delegate = PiPDelegate(
            onActiveChange: { [weak self] active in self?.pictureInPictureChanged(active: active) },
            onRestore: { [weak self] completion in
                guard let self else {
                    completion(false)
                    return
                }
                self.restorePictureInPicture(completion: completion)
            })
        controller?.delegate = delegate
        pipDelegate = delegate
        pipController = controller
    }

    func pictureInPictureChanged(active: Bool) {
        isPiPActive = active
        guard currentVideo != nil else { return }
        if active {
            vm.updateNowPlayingInfo()
            minimize()
        } else if presentation == .pictureInPicture {
            presentation = .miniPlayer
        }
    }

    func restorePictureInPicture(completion: @escaping (Bool) -> Void) {
        pipRestoreCompletion?(false)
        pipRestoreCompletion = nil
        guard currentVideo != nil else {
            completion(false)
            return
        }
        let wasFullScreen = presentation == .fullScreen
        pipRestoreCompletion = completion
        expand()
        if wasFullScreen { completePictureInPictureRestoration() }
    }

    /// Called after UIKit presentation and layout, not when SwiftUI requests the cover.
    func completePictureInPictureRestoration() {
        guard presentation == .fullScreen, playerHostView.window != nil,
            !playerHostView.bounds.isEmpty
        else { return }
        let completion = pipRestoreCompletion
        pipRestoreCompletion = nil
        completion?(true)
    }
}
#endif
