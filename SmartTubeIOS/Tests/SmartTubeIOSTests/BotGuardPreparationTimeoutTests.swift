#if canImport(WebKit)
import Foundation
import JavaScriptCore
import Testing

@testable import SmartTubeIOS

@Suite("BotGuard preparation timeout ownership (PLAN-0011)")
@MainActor
struct BotGuardPreparationTimeoutTests {
    @Test func pipelineFunctionAcceptsAttemptIDWithoutExecutingNetworkCode() throws {
        let context = try #require(JSContext())
        let source = BotGuardWebViewRunner.pipelineJS(attemptID: UUID())
        let encoded = try JSONEncoder().encode(source)
        let argument = try #require(String(data: encoded, encoding: .utf8))
        let function = context.evaluateScript("new Function(\(argument))")
        #expect(context.exception == nil)
        #expect(function?.isObject == true)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }

    @Test(arguments: [true, false])
    func oldTimeoutAndCallbacksCannotFinishNewAttempt(succeeded: Bool) async throws {
        let runner = BotGuardWebViewRunner()
        var ids: [UUID] = []
        var timers: [CheckedContinuation<Void, Never>] = []
        var cancelledTimers: [Bool] = []
        let delay: @MainActor () async throws -> Void = {
            await withCheckedContinuation { timers.append($0) }
            cancelledTimers.append(Task.isCancelled)
        }
        let first = Task { @MainActor in
            await runner.runPreparation(waitForTimeout: delay) { ids.append($0) }
        }
        await waitUntil { timers.count == 1 }
        let oldID = try #require(ids.first)
        runner.finishPreparation(
            attemptID: oldID,
            result: .init(
                hasMinter: succeeded, websafeToken: nil, ttl: 1,
                integrityTokenLen: 0, webVisitorData: "first"))
        #expect(await first.value.hasMinter == succeeded)

        var secondReturned = false
        let second = Task { @MainActor in
            let result = await runner.runPreparation(waitForTimeout: delay) { ids.append($0) }
            secondReturned = true
            return result
        }
        await waitUntil { timers.count == 2 }
        let currentID = try #require(ids.last)
        #expect(currentID != oldID)

        // Simulate a late injection/navigation completion and a message from the old script.
        runner.finishPreparation(attemptID: oldID)
        runner.handlePrepareMessage([
            "attemptID": oldID.uuidString, "success": true,
            "hasMinter": true, "webVisitorData": "stale",
        ])
        timers[0].resume()
        await waitUntil { !cancelledTimers.isEmpty }
        #expect(cancelledTimers == [true])
        #expect(!secondReturned)
        #expect(runner.webVisitorData == "first")

        timers[1].resume()
        let timedOut = await second.value
        #expect(!timedOut.hasMinter)
        #expect(secondReturned)
        #expect(cancelledTimers == [true, false])

        // Completion after timeout is harmless and cannot publish stale metadata.
        runner.handlePrepareMessage([
            "attemptID": currentID.uuidString, "success": true,
            "hasMinter": true, "webVisitorData": "too-late",
        ])
        runner.finishPreparation(attemptID: currentID)
        #expect(runner.webVisitorData.isEmpty)
    }

    @Test func currentMessageCompletesOnceAndCancelsTimer() async throws {
        let runner = BotGuardWebViewRunner()
        var id: UUID?
        var timer: CheckedContinuation<Void, Never>?
        var cancelled: Bool?
        let task = Task { @MainActor in
            await runner.runPreparation(
                waitForTimeout: {
                    await withCheckedContinuation { timer = $0 }
                    cancelled = Task.isCancelled
                }, launch: { id = $0 })
        }
        await waitUntil { timer != nil }
        let attemptID = try #require(id)
        runner.handlePrepareMessage([
            "attemptID": attemptID.uuidString, "success": true,
            "hasMinter": true, "webVisitorData": "current",
        ])
        runner.finishPreparation(attemptID: attemptID)
        #expect(await task.value.webVisitorData == "current")
        timer?.resume()
        await waitUntil { cancelled != nil }
        #expect(cancelled == true)
        #expect(runner.webVisitorData == "current")
    }
}
#endif
