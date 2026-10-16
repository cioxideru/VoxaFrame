#if canImport(WebKit)
import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("BotGuard preparation waiters (PLAN-0011)")
@MainActor
struct BotGuardPreparationWaiterTests {
    private var result: BotGuardWebViewRunner.PrepareResult {
        .init(hasMinter: false, websafeToken: nil, ttl: 1, integrityTokenLen: 0, webVisitorData: "test")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }

    @Test func cancelledWaiterLeavesSharedPreparationAndOtherWaiterAlive() async {
        let runner = BotGuardWebViewRunner()
        var finish: CheckedContinuation<BotGuardWebViewRunner.PrepareResult, Never>?
        var firstReturned = false
        var secondReturned = false
        var starts = 0
        let first = Task { @MainActor in
            let value = await runner.prepare {
                starts += 1
                return await withCheckedContinuation { finish = $0 }
            }
            firstReturned = true
            return value
        }
        await waitUntil { finish != nil }
        let second = Task { @MainActor in
            let value = await runner.prepare {
                starts += 1
                return result
            }
            secondReturned = true
            return value
        }
        await waitUntil { runner.prepareWaiters.count == 2 }
        first.cancel()
        await waitUntil { firstReturned }
        #expect(!secondReturned)
        #expect(starts == 1)
        finish?.resume(returning: result)
        #expect(await first.value == nil)
        #expect(await second.value == nil)  // Existing joiner return contract.
        #expect(secondReturned)
        #expect(runner.prepareWaiters.isEmpty)
    }

    @Test func cancellationBeforeRegistrationDoesNotStartPreparation() async {
        let runner = BotGuardWebViewRunner()
        var started = false
        let waiter = Task { @MainActor in
            await runner.prepare {
                started = true
                return result
            }
        }
        waiter.cancel()
        #expect(await waiter.value == nil)
        #expect(!started)
        #expect(runner.prepareWaiters.isEmpty)
    }

    @Test(arguments: [true, false])
    func cancellationRacingCompletionResumesOnce(cancelFirst: Bool) async {
        let runner = BotGuardWebViewRunner()
        var finish: CheckedContinuation<BotGuardWebViewRunner.PrepareResult, Never>?
        var completed = false
        let waiter = Task { @MainActor in
            await runner.prepare {
                let value = await withCheckedContinuation { finish = $0 }
                completed = true
                return value
            }
        }
        await waitUntil { finish != nil }
        if cancelFirst { waiter.cancel() }
        finish?.resume(returning: result)
        let value = await waiter.value
        if !cancelFirst { waiter.cancel() }
        #expect((value == nil) == cancelFirst)
        await waitUntil { completed }
        await waitUntil { runner.prepareWaiters.isEmpty }
        let next = await runner.prepare { result }
        #expect(next?.webVisitorData == "test")
    }

    @Test func initiatingCallerReceivesResult() async {
        let runner = BotGuardWebViewRunner()
        let value = await runner.prepare { result }
        #expect(value?.webVisitorData == "test")
        #expect(runner.prepareWaiters.isEmpty)
    }
}
#endif
