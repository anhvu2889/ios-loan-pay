import Foundation
import LoanPayDomain

/// Durable queue of deferred writes: file-backed, state-machine per
/// operation (pending → inflight → done/failed).
///
/// LANG: an actor — enqueues arrive from swipe actions on the main actor
/// while the drainer mutates states from a background task; the array +
/// file pair must change atomically with respect to both.
public actor OutboxStore: OutboxEnqueuing {
    public struct Stats: Equatable, Sendable {
        public let pendingCount: Int
        public let failedCount: Int

        public var isEmpty: Bool { pendingCount == 0 && failedCount == 0 }
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var operations: [OutboxOperation] = []
    private var isLoaded = false
    private var statsContinuations: [UUID: AsyncStream<Stats>.Continuation] = [:]

    public init(
        directoryName: String = "LoanPayOutbox",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("outbox.json")
        self.now = now
    }

    // MARK: - Enqueue

    public func enqueue(_ payload: OutboxPayload) async throws {
        ensureLoaded()
        let operation = OutboxOperation(
            id: UUID(),
            payload: payload,
            // FINTECH: the key is minted HERE, once, at enqueue — every
            // delivery attempt tonight or next week presents the same
            // bytes, so the support desk gets ONE callback ticket no
            // matter how many retries it took.
            idempotencyKey: .generate(),
            createdAt: now()
        )
        operations.append(operation)
        persist()
    }

    // MARK: - Drainer interface

    /// The next operation the drainer should work on, marked inflight.
    public func checkOutNextPending() -> OutboxOperation? {
        ensureLoaded()
        // WHY inflight ops count as claimable: an inflight state on LOAD
        // means the app died mid-delivery. The idempotency key makes
        // re-delivery safe; leaving them stranded would not be.
        guard let index = operations.firstIndex(where: {
            $0.state == .pending || $0.state == .inflight
        }) else {
            return nil
        }
        operations[index].state = .inflight
        persist()
        return operations[index]
    }

    public func markDone(_ id: UUID) {
        // WHY remove instead of keeping a .done tombstone: the queue's job
        // is undelivered work. History belongs to the server; a growing
        // done-list in a PII store is liability, not auditability.
        operations.removeAll { $0.id == id }
        persist()
    }

    public func recordFailedAttempt(_ id: UUID, maxAttempts: Int) -> OutboxOperation? {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return nil }
        operations[index].attempts += 1
        operations[index].state = operations[index].attempts >= maxAttempts ? .failed : .pending
        persist()
        return operations[index]
    }

    /// Manual retry: failed operations rejoin the queue with a clean
    /// attempt budget.
    public func retryAllFailed() {
        ensureLoaded()
        for index in operations.indices where operations[index].state == .failed {
            operations[index].state = .pending
            operations[index].attempts = 0
        }
        persist()
    }

    /// Logout sweep: queued payloads reference the user's loans — they
    /// leave with the session.
    public func removeAll() {
        ensureLoaded()
        operations.removeAll()
        persist()
    }

    // MARK: - Observation

    public func currentStats() -> Stats {
        ensureLoaded()
        return Stats(
            pendingCount: operations.count(where: { $0.state == .pending || $0.state == .inflight }),
            failedCount: operations.count(where: { $0.state == .failed })
        )
    }

    /// Pushes stats on every mutation; the sync badge just `for await`s.
    public func statsUpdates() -> AsyncStream<Stats> {
        ensureLoaded()
        let id = UUID()
        return AsyncStream { continuation in
            statsContinuations[id] = continuation
            continuation.yield(currentStats())
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([OutboxOperation].self, from: data) else {
            return
        }
        operations = loaded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(operations) else { return }
        // FINTECH: queued payloads name loans and topics — PII at rest,
        // same protection class as the cache.
        #if os(iOS)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: fileURL, options: [.atomic])
        #endif
        let stats = currentStats()
        for continuation in statsContinuations.values {
            continuation.yield(stats)
        }
    }

    private func removeContinuation(_ id: UUID) {
        statsContinuations[id] = nil
    }
}
