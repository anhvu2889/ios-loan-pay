import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

/// Scripted deliverer: records every attempt's operation (and key), plays
/// back a per-call result script, and can block on a gate.
actor SpyDeliverer: OutboxDelivering {
    private(set) var attempts: [OutboxOperation] = []
    private var script: [Result<Void, DomainError>]
    private let alwaysFail: Bool

    init(script: [Result<Void, DomainError>] = [], alwaysFail: Bool = false) {
        self.script = script
        self.alwaysFail = alwaysFail
    }

    func deliver(_ operation: OutboxOperation) async throws {
        attempts.append(operation)
        if alwaysFail {
            throw DomainError.offline
        }
        guard !script.isEmpty else { return }
        try script.removeFirst().get()
    }
}

actor SleepRecorder: Sleeper {
    private(set) var recordedDelays: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDelays.append(duration)
    }
}

@Suite struct OutboxDrainerTests {
    private func makeStore() -> OutboxStore {
        OutboxStore(directoryName: "DrainerTests-\(UUID().uuidString)")
    }

    private func makeDrainer(
        store: OutboxStore,
        deliverer: SpyDeliverer,
        sleeper: SleepRecorder = SleepRecorder(),
        maxAttempts: Int = 3
    ) -> OutboxDrainer {
        OutboxDrainer(
            store: store,
            deliverer: deliverer,
            sleeper: sleeper,
            logger: SilentDataLogger(),
            maxAttempts: maxAttempts
        )
    }

    @Test func drainDeliversEverythingAndEmptiesTheQueue() async throws {
        let store = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        try await store.enqueue(.supportCallback(topic: "device", loanID: nil))
        let deliverer = SpyDeliverer()
        let drainer = makeDrainer(store: store, deliverer: deliverer)

        await drainer.drainNow()

        #expect(await deliverer.attempts.count == 2)
        #expect(await store.currentStats().isEmpty)
    }

    @Test func retriesReuseTheSameIdempotencyKey() async throws {
        let store = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        // Fail twice, then succeed.
        let deliverer = SpyDeliverer(script: [.failure(.timeout), .failure(.timeout), .success(())])
        let sleeper = SleepRecorder()
        let drainer = makeDrainer(store: store, deliverer: deliverer, sleeper: sleeper)

        await drainer.drainNow()

        let attempts = await deliverer.attempts
        #expect(attempts.count == 3)
        // FINTECH: every attempt presented the SAME key — the support desk
        // sees one ticket, not three.
        #expect(Set(attempts.map(\.idempotencyKey)).count == 1)
        #expect(await store.currentStats().isEmpty)
        // Capped exponential backoff between attempts: 0.5s then 1s.
        await #expect(sleeper.recordedDelays == [.milliseconds(500), .milliseconds(1000)])
    }

    @Test func operationParksAsFailedAfterMaxAttempts() async throws {
        let store = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        let deliverer = SpyDeliverer(alwaysFail: true)
        let drainer = makeDrainer(store: store, deliverer: deliverer, maxAttempts: 3)

        await drainer.drainNow()

        #expect(await deliverer.attempts.count == 3)
        let stats = await store.currentStats()
        #expect(stats.failedCount == 1)
        #expect(stats.pendingCount == 0)
    }

    @Test func manualRetryRevivesFailedOperations() async throws {
        let store = makeStore()
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        let failing = SpyDeliverer(alwaysFail: true)
        await makeDrainer(store: store, deliverer: failing, maxAttempts: 1).drainNow()
        #expect(await store.currentStats().failedCount == 1)

        let succeeding = SpyDeliverer()
        await makeDrainer(store: store, deliverer: succeeding).retryFailed()

        #expect(await store.currentStats().isEmpty)
        #expect(await succeeding.attempts.count == 1)
    }

    @Test func backoffScheduleIsCapped() {
        #expect(OutboxDrainer.backoffDelay(afterAttempts: 1) == .milliseconds(500))
        #expect(OutboxDrainer.backoffDelay(afterAttempts: 2) == .milliseconds(1000))
        #expect(OutboxDrainer.backoffDelay(afterAttempts: 5) == .milliseconds(8000))
        // The cap: even attempt 40 waits at most 30s.
        #expect(OutboxDrainer.backoffDelay(afterAttempts: 40) == .milliseconds(30_000))
    }
}

struct SilentDataLogger: AppLogger {
    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {}
}
