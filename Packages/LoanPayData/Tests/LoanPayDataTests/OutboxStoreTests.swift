import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct OutboxStoreTests {
    private func makeStore(directoryName: String = "OutboxTests-\(UUID().uuidString)") -> (OutboxStore, String) {
        (OutboxStore(directoryName: directoryName), directoryName)
    }

    @Test func enqueuePersistsAcrossStoreInstances() async throws {
        let (store, directory) = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: LoanID("loan-1")))

        // A brand-new store over the same directory = app relaunch.
        let reloaded = OutboxStore(directoryName: directory)
        let stats = await reloaded.currentStats()
        #expect(stats.pendingCount == 1)

        let operation = await reloaded.checkOutNextPending()
        #expect(operation?.payload == .supportCallback(topic: "billing", loanID: LoanID("loan-1")))
    }

    @Test func checkoutMarksInflightAndDoneRemoves() async throws {
        let (store, _) = makeStore()
        try await store.enqueue(.supportCallback(topic: "device", loanID: nil))

        let operation = try #require(await store.checkOutNextPending())
        #expect(operation.state == .inflight)

        await store.markDone(operation.id)
        #expect(await store.currentStats().isEmpty)
        #expect(await store.checkOutNextPending() == nil)
    }

    @Test func interruptedInflightOperationIsReclaimable() async throws {
        let (store, directory) = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        _ = await store.checkOutNextPending() // app "dies" here, mid-delivery

        let relaunched = OutboxStore(directoryName: directory)
        // The stranded inflight op is claimable again — the idempotency key
        // makes the re-delivery safe.
        #expect(await relaunched.checkOutNextPending() != nil)
    }

    @Test func failuresCountUpAndParkAsFailedAtTheCap() async throws {
        let (store, _) = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        let operation = try #require(await store.checkOutNextPending())

        let afterFirst = await store.recordFailedAttempt(operation.id, maxAttempts: 2)
        #expect(afterFirst?.state == .pending)
        #expect(afterFirst?.attempts == 1)

        _ = await store.checkOutNextPending()
        let afterSecond = await store.recordFailedAttempt(operation.id, maxAttempts: 2)
        #expect(afterSecond?.state == .failed)

        let stats = await store.currentStats()
        #expect(stats.failedCount == 1)
        #expect(stats.pendingCount == 0)
    }

    @Test func manualRetryReturnsFailedOperationsToPendingWithFreshBudget() async throws {
        let (store, _) = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        let operation = try #require(await store.checkOutNextPending())
        _ = await store.recordFailedAttempt(operation.id, maxAttempts: 1)
        #expect(await store.currentStats().failedCount == 1)

        await store.retryAllFailed()

        let retried = try #require(await store.checkOutNextPending())
        #expect(retried.attempts == 0)
        // The identity — and the idempotency key — survive the retry.
        #expect(retried.id == operation.id)
        #expect(retried.idempotencyKey == operation.idempotencyKey)
    }

    @Test func statsStreamPushesOnMutation() async throws {
        let (store, _) = makeStore()
        let stream = await store.statsUpdates()
        var iterator = stream.makeAsyncIterator()

        // Initial state arrives immediately.
        #expect(await iterator.next()?.isEmpty == true)

        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        #expect(await iterator.next()?.pendingCount == 1)
    }

    @Test func removeAllSweepsTheQueue() async throws {
        let (store, directory) = makeStore()
        try await store.enqueue(.supportCallback(topic: "a", loanID: nil))
        try await store.enqueue(.supportCallback(topic: "b", loanID: nil))

        await store.removeAll()

        #expect(await store.currentStats().isEmpty)
        // And durably: a relaunch sees nothing.
        let reloaded = OutboxStore(directoryName: directory)
        #expect(await reloaded.currentStats().isEmpty)
    }
}
