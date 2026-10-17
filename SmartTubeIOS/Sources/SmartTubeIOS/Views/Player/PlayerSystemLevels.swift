#if os(iOS)
import MediaPlayer
import UIKit

/// Owns temporary display brightness; volume belongs to the system's volume control.
@MainActor
final class PlayerSystemLevels {
    let volumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 160, height: 44))
    private weak var screen: UIScreen?
    private var originalBrightness: CGFloat?
    private var appliedBrightness: CGFloat?

    init() {
        // The player already owns an AVRoutePickerView; this control only supplies volume.
        volumeView.showsRouteButton = false
        volumeView.isUserInteractionEnabled = false
        volumeView.accessibilityElementsHidden = true
    }

    func value(for level: PlayerPanGesture.Level, in view: UIView) -> CGFloat? {
        switch level {
        case .brightness:
            guard let screen = view.window?.windowScene?.screen else { return nil }
            self.screen = screen
            if originalBrightness == nil { originalBrightness = screen.brightness }
            return screen.brightness
        case .volume:
            // Read and write the same system control, even before playback activates its audio session.
            guard let slider = volumeSlider else { return nil }
            return CGFloat(slider.value)
        }
    }

    func set(_ value: CGFloat, for level: PlayerPanGesture.Level) -> CGFloat? {
        switch level {
        case .brightness:
            guard let screen else { return nil }
            screen.brightness = value
            appliedBrightness = screen.brightness
            return screen.brightness
        case .volume:
            guard let slider = volumeSlider else { return nil }
            slider.setValue(Float(value), animated: false)
            slider.sendActions(for: .valueChanged)
            return CGFloat(slider.value)
        }
    }

    func restoreBrightness() {
        if let screen, let originalBrightness, let appliedBrightness,
            abs(screen.brightness - appliedBrightness) < 0.005
        {
            screen.brightness = originalBrightness
        }
        originalBrightness = nil
        appliedBrightness = nil
    }

    private var volumeSlider: UISlider? {
        // MPVolumeView documents its slider as UISlider; fixed-volume routes omit it.
        volumeView.subviews.compactMap { $0 as? UISlider }.first { $0.isEnabled && !$0.isHidden }
    }
}
#endif
