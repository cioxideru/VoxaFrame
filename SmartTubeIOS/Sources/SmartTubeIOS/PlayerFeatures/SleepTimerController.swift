import Foundation

// MARK: - Sleep Timer
//
// Used by PlaybackViewModel. The pause action is supplied per call.

/// Counts down to a pause action, cancellable by starting a new countdown
/// or passing `nil`.
@MainActor
@Observable
final class SleepTimerController {

    private(set) var sleepTimerMinutes: Int? = nil

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Activates (or cancels) the sleep timer.
    /// - Parameters:
    ///   - minutes: Nil cancels any running timer; a positive value starts a new countdown.
    ///   - onFire: Called when the countdown elapses (e.g. pause playback).
    func setSleepTimer(minutes: Int?, onFire: @escaping () -> Void) {
        task?.cancel()
        task = nil
        sleepTimerMinutes = minutes
        guard let minutes else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard let self, !Task.isCancelled else { return }
            self.sleepTimerMinutes = nil
            onFire()
        }
    }
}
