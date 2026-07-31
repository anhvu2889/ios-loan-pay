import Foundation

/// A bounded backoff schedule: one entry per retry, consumed in order.
///
/// FINTECH: retry is opt-in per call site, never ambient. Reads may retry;
/// payment submission must NOT — a timed-out payment may have landed, and
/// only a human, resubmitting with the same idempotency key, may try again.
/// Keeping the policy as a value the caller passes (rather than baking retry
/// into a repository) keeps that distinction visible at every call site.
public struct RetryPolicy: Sendable {
    public let backoffDelays: [Duration]

    public init(backoffDelays: [Duration]) {
        self.backoffDelays = backoffDelays
    }

    /// Two retries, 0.5s then 1s — enough to ride out a flaky cell handover
    /// on the first screen the user sees, short enough not to feel hung.
    public static let initialListLoad = RetryPolicy(
        backoffDelays: [.milliseconds(500), .seconds(1)]
    )

    // LANG: the operation closure is not @escaping — `execute` awaits it
    // inline and never stores it, so callers may capture locals freely and
    // the compiler proves the closure's lifetime ends with the call.
    public func execute<T: Sendable>(
        sleeper: any Sleeper,
        _ operation: () async throws -> T
    ) async throws -> T {
        var remainingDelays = backoffDelays[...]
        while true {
            do {
                return try await operation()
            } catch let error as DomainError where error.isRetryable {
                guard let delay = remainingDelays.popFirst() else { throw error }
                // WHY: the sleep is the cancellation point. If the user
                // leaves the screen mid-backoff, the injected sleeper throws
                // CancellationError and the whole retry loop unwinds — no
                // orphaned attempt fires after the caller stopped caring.
                try await sleeper.sleep(for: delay)
            }
            // WHY: non-retryable DomainErrors and non-domain errors
            // (including CancellationError) fall through the `where` clause
            // and propagate on the first attempt — retrying them would just
            // repeat the same failure slower.
        }
    }
}
