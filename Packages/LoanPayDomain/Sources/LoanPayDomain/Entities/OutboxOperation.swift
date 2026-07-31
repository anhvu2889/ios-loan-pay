import Foundation

/// One queued write, persisted until it has been delivered.
public struct OutboxOperation: Codable, Hashable, Sendable, Identifiable {
    public enum State: String, Codable, Hashable, Sendable {
        case pending
        /// Handed to the network; if the app dies here, the drainer treats it
        /// as pending again — the idempotency key makes the replay safe.
        case inflight
        /// Gave up after the attempt cap; waits for a manual retry.
        case failed
        case done
    }

    public let id: UUID
    public let payload: OutboxPayload
    // FINTECH: minted at enqueue time and immutable for the operation's whole
    // life, so every delivery attempt — tonight, tomorrow, after a reinstall
    // of connectivity — presents the same key and the server can collapse
    // duplicates.
    public let idempotencyKey: IdempotencyKey
    public let createdAt: Date
    public var state: State
    public var attempts: Int

    public init(
        id: UUID,
        payload: OutboxPayload,
        idempotencyKey: IdempotencyKey,
        createdAt: Date,
        state: State = .pending,
        attempts: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.state = state
        self.attempts = attempts
    }
}
