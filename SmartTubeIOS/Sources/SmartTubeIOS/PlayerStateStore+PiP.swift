#if os(iOS)
import AVKit
import os

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
            onWillStart: { [weak self, weak controller] in
                guard let self, let controller, self.pipController === controller else { return }
                pictureInPictureWillStart()
            },
            onActiveChange: { [weak self, weak controller] active in
                guard let self, let controller, self.pipController === controller else { return }
                pictureInPictureChanged(active: active)
            },
            onRestore: { [weak self, weak controller] completion in
                guard let self, let controller, self.pipController === controller else {
                    completion(false)
                    return
                }
                self.restorePictureInPicture(completion: completion)
            })
        controller?.delegate = delegate
        pipDelegate = delegate
        pipController = controller
    }

    func pictureInPictureWillStart() {
        pipStartRequestID = fullScreenRequestID
        storeLog.notice(
            "[PlayerStateStore] PiP willStart presentation=\(String(describing: self.presentation), privacy: .public)")
    }

    func pictureInPictureChanged(active: Bool) {
        isPiPActive = active
        if !active {
            pipStartRequestID = nil
            let completion = pipRestoreCompletion
            pipRestoreCompletion = nil
            completion?(false)
        }
        guard currentVideo != nil else {
            if active { pipController?.stopPictureInPicture() }
            return
        }
        if active {
            // A library tap/restore can expand while AVKit is still entering PiP for the old cover.
            guard pipStartRequestID == fullScreenRequestID, pipRestoreCompletion == nil else {
                storeLog.notice("[PlayerStateStore] PiP didStart ignored — newer full-screen request or restoration")
                pipController?.stopPictureInPicture()
                return
            }
            vm.updateNowPlayingInfo()
            minimize(reason: "pip-did-start")
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
