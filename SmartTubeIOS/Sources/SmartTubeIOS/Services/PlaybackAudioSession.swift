import AVFoundation
import Foundation
import SmartTubeIOSCore
import os

/// The process-wide audio session has one owner, independent of the number of players.
/// Native calls are synchronous on this actor, so an activation cannot overlap a release.
actor PlaybackAudioSession {
    static let shared = PlaybackAudioSession()

    struct Driver: Sendable {
        var configure: @Sendable () throws -> Void
        var setActive: @Sendable (Bool) throws -> Void

        static let system = Driver(
            configure: {
                #if canImport(UIKit)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                #endif
            },
            setActive: { active in
                #if canImport(UIKit)
                try AVAudioSession.sharedInstance().setActive(
                    active, options: active ? [] : .notifyOthersOnDeactivation)
                #endif
            })
    }

    // The lock protects only intent, never native I/O. MainActor can revoke a pending
    // request even while setActive is blocking the actor's executor.
    private final class Intent: @unchecked Sendable {
        private let lock = NSLock()
        private var current: UUID?

        func begin() -> UUID {
            lock.withLock {
                let id = UUID()
                current = id
                return id
            }
        }

        func invalidate(_ id: UUID) {
            lock.withLock { if current == id { current = nil } }
        }

        func contains(_ id: UUID) -> Bool { lock.withLock { current == id } }
        var isEmpty: Bool { lock.withLock { current == nil } }
    }

    nonisolated private let intent = Intent()
    private let driver: Driver
    private var configured = false
    private var activeOwner: UUID?
    private let log = Logger(subsystem: appSubsystem, category: "AudioSession")

    init(driver: Driver = .system) { self.driver = driver }

    nonisolated func begin() -> UUID { intent.begin() }
    nonisolated func invalidate(_ id: UUID) { intent.invalidate(id) }
    nonisolated func isCurrent(_ id: UUID) -> Bool { intent.contains(id) }

    func activate(_ id: UUID, force: Bool = false) throws -> Bool {
        guard accepts(id) else { return false }
        if activeOwner == id, !force { return true }
        if !configured {
            try measured("configure") { try driver.configure() }
            configured = true
        }
        guard accepts(id) else { return false }
        try measured("activate") { try driver.setActive(true) }
        activeOwner = id
        return accepts(id)
    }

    private func accepts(_ id: UUID) -> Bool {
        guard !Task.isCancelled, intent.contains(id) else {
            if Task.isCancelled { intent.invalidate(id) }
            release(id)
            return false
        }
        return true
    }

    func release(_ id: UUID) {
        // A replacement can be stopped before reaching activate(). With no remaining
        // intent, release the previous native owner too; a newer live intent protects it.
        guard activeOwner != nil, activeOwner == id || intent.isEmpty else { return }
        do {
            try measured("deactivate") { try driver.setActive(false) }
            activeOwner = nil
        } catch {
            // Keep ownership so a later release can retry without touching a newer owner.
        }
    }

    private func measured(_ operation: String, body: () throws -> Void) throws {
        let start = ContinuousClock.now
        do {
            try body()
            log.notice(
                "\(operation, privacy: .public) completed in \(String(describing: start.duration(to: .now)), privacy: .public)"
            )
        } catch {
            log.error(
                "\(operation, privacy: .public) failed in \(String(describing: start.duration(to: .now)), privacy: .public)"
            )
            throw error
        }
    }
}
