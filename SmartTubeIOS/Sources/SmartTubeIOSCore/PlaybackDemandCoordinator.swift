import Foundation

/// One decision for optional work; playback adapters own independent demand leases.
@MainActor
public final class PlaybackDemandCoordinator {
    public enum Phase: Sendable { case inactive, preparing, buffering, playing }
    public private(set) var isYielding = false
    private var owners: [UUID: Phase] = [:]
    private var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let waitForRecovery: @MainActor () async throws -> Void
    private let waitForBudget: @MainActor () async throws -> Void
    private var recovery: Task<Void, Never>?
    private var budget: Task<Void, Never>?
    private var episode: UUID?
    private var recoveryID: UUID?
    private var budgetExhausted = false

    public init(
        waitForRecovery: @escaping @MainActor () async throws -> Void,
        waitForBudget: @escaping @MainActor () async throws -> Void
    ) {
        self.waitForRecovery = waitForRecovery
        self.waitForBudget = waitForBudget
    }

    deinit {
        recovery?.cancel()
        budget?.cancel()
        for continuation in subscribers.values { continuation.finish() }
    }

    public func changes() -> AsyncStream<Bool> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(isYielding)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    public func update(owner: UUID, phase: Phase) {
        if phase == .inactive { owners.removeValue(forKey: owner) } else { owners[owner] = phase }
        let preparing = owners.values.contains(.preparing)
        let urgent = preparing || owners.values.contains(.buffering)
        if urgent {
            recovery?.cancel()
            recovery = nil
            recoveryID = nil
            if episode == nil { episode = UUID() }
            if preparing {
                budget?.cancel()
                budget = nil
                budgetExhausted = false
                publish(true)
            } else if !budgetExhausted {
                publish(true)
                guard budget == nil else { return }
                let id = episode
                let wait = waitForBudget
                budget = Task { [weak self] in
                    do { try await wait() } catch { return }
                    guard !Task.isCancelled, let self, self.episode == id else { return }
                    // Allow progress for the rest of a prolonged stall, without restart cycles.
                    self.budgetExhausted = true
                    self.publish(false)
                    self.budget = nil
                }
            }
        } else {
            guard episode != nil, recovery == nil else { return }
            let id = UUID()
            recoveryID = id
            let wait = waitForRecovery
            recovery = Task { [weak self] in
                do { try await wait() } catch { return }
                guard !Task.isCancelled, let self, self.recoveryID == id else { return }
                self.budget?.cancel()
                self.budget = nil
                self.episode = nil
                self.budgetExhausted = false
                self.recovery = nil
                self.recoveryID = nil
                self.publish(false)
            }
        }
    }

    public func remove(owner: UUID) { update(owner: owner, phase: .inactive) }

    private func publish(_ value: Bool) {
        guard isYielding != value else { return }
        isYielding = value
        for continuation in subscribers.values { continuation.yield(value) }
    }
}
