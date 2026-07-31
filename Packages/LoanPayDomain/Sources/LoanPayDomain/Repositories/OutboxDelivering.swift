import Foundation

/// Performs the actual network delivery of one queued operation.
///
/// ARCH: the drainer owns WHEN and HOW OFTEN; this seam owns HOW. Splitting
/// them means drain scheduling, backoff and attempt caps are tested with a
/// scripted deliverer — no network, no mock server, no sleeps.
public protocol OutboxDelivering: Sendable {
    /// Must be safe to call again for the same operation — the operation's
    /// idempotency key travels with it precisely so replays collapse
    /// server-side.
    func deliver(_ operation: OutboxOperation) async throws
}
