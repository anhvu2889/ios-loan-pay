import Foundation
import LoanPayDomain

/// Works the outbox down: checkout → deliver → done/failed, with capped
/// exponential backoff between failed attempts.
///
/// Triggered by connectivity regain, app foreground, and background app
/// refresh — the drainer itself doesn't know or care which.
public actor OutboxDrainer {
    private let store: OutboxStore
    private let deliverer: any OutboxDelivering
    private let sleeper: any Sleeper
    private let logger: any AppLogger
    /// After this many failed attempts an operation parks in `.failed` and
    /// waits for a human tap — endless silent retries hide real breakage.
    private let maxAttempts: Int
    private var isDraining = false

    public init(
        store: OutboxStore,
        deliverer: any OutboxDelivering,
        sleeper: any Sleeper,
        logger: any AppLogger,
        maxAttempts: Int = 3
    ) {
        self.store = store
        self.deliverer = deliverer
        self.sleeper = sleeper
        self.logger = logger
        self.maxAttempts = maxAttempts
    }

    /// Drains until the queue has no claimable work. Safe to call from
    /// every trigger at once — reentry collapses into the running drain.
    public func drainNow() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while !Task.isCancelled, let operation = await store.checkOutNextPending() {
            do {
                try await deliverer.deliver(operation)
                await store.markDone(operation.id)
                logger.log(.info, category: .outbox, "outbox operation delivered")
            } catch is CancellationError {
                // WHY leave it inflight and stop: cancellation means our
                // window closed (background task expired, app suspending).
                // The inflight state is reclaimed by the next drain, and
                // the idempotency key makes the re-delivery safe.
                return
            } catch {
                guard let updated = await store.recordFailedAttempt(operation.id, maxAttempts: maxAttempts) else {
                    continue
                }
                if updated.state == .failed {
                    logger.log(.warning, category: .outbox, "outbox operation parked as failed after max attempts")
                    continue // next operation; this one waits for manual retry
                }
                do {
                    // WHY backoff between attempts of the SAME operation:
                    // the failure is usually the network or the endpoint,
                    // and hammering an unhealthy endpoint at line rate
                    // turns a blip into an outage. Capped so a long queue
                    // never waits minutes between items.
                    try await sleeper.sleep(for: Self.backoffDelay(afterAttempts: updated.attempts))
                } catch {
                    return // cancelled mid-backoff; queue state is safe
                }
            }
        }
    }

    /// Failed → pending with a fresh attempt budget, then drain.
    public func retryFailed() async {
        await store.retryAllFailed()
        await drainNow()
    }

    /// 0.5s, 1s, 2s, 4s… capped at 30s.
    static func backoffDelay(afterAttempts attempts: Int) -> Duration {
        let exponent = min(attempts - 1, 6)
        let milliseconds = min(500 * (1 << exponent), 30_000)
        return .milliseconds(milliseconds)
    }
}
