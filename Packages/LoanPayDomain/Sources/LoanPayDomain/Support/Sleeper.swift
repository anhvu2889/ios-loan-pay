import Foundation

// WHY: every piece of time-based behavior (retry backoff, search debounce,
// outbox drain schedule) sleeps through this seam instead of calling
// Task.sleep directly. Tests inject an instant, recording implementation and
// assert the exact delays — the whole suite runs with zero real sleeps.
public protocol Sleeper: Sendable {
    /// Must throw `CancellationError` if the surrounding task is cancelled,
    /// exactly like `Task.sleep` — callers rely on cancellation propagating
    /// out of a backoff wait.
    func sleep(for duration: Duration) async throws
}

public struct ContinuousSleeper: Sleeper {
    public init() {}

    // MODERN: Task.sleep(for:) takes a typed `Duration` and is cancellation-
    // aware. The pre-2021 shape was DispatchQueue.asyncAfter with a manual
    // cancellation flag — fire-and-forget, easy to leak, impossible to await.
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
