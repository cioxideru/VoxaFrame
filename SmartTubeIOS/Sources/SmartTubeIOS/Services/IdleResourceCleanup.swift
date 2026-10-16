import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Owns the short reuse window for parked playback and idle browser resources.
@MainActor
final class IdleResourceCleanup {
    private let wait: @MainActor () async throws -> Void
    private var timer: Task<Void, Never>?
    private var pressureTask: Task<Void, Never>?
    private var generation: UUID?
    private var release: (@MainActor () -> Void)?
    private var users = 0

    static var memoryWarningNotification: Notification.Name? {
        #if canImport(UIKit)
        UIApplication.didReceiveMemoryWarningNotification
        #else
        nil
        #endif
    }

    init(
        pressureNotification: Notification.Name? = IdleResourceCleanup.memoryWarningNotification,
        wait: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: PlaybackTuning.idleResourceRetention)
        }
    ) {
        self.wait = wait
        if let pressureNotification {
            let notifications = NotificationCenter.default.notifications(named: pressureNotification)
                .map { _ in () }
            pressureTask = Task { [weak self] in
                for await _ in notifications {
                    guard !Task.isCancelled else { return }
                    self?.releaseNow()
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        pressureTask?.cancel()
    }

    func cancel() {
        timer?.cancel()
        timer = nil
        generation = nil
        release = nil
    }

    func beginUse() {
        users += 1
        cancel()
    }

    func endUse(release: @escaping @MainActor () -> Void) {
        users -= 1
        if users == 0 { schedule(release: release) }
    }

    func schedule(release: @escaping @MainActor () -> Void) {
        cancel()
        guard users == 0 else { return }
        self.release = release
        let id = UUID()
        generation = id
        let wait = self.wait
        timer = Task { [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, self?.generation == id else { return }
            self?.releaseNow()
        }
    }

    func releaseNow() {
        let action = release
        cancel()
        action?()
    }
}
