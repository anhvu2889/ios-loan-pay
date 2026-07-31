import Foundation

// ARCH: Features that fire offline-tolerant writes (e.g. "request a
// callback") depend on this one-method contract, not on the outbox store,
// drainer or file layout. The narrow seam keeps feature packages compilable
// against Domain alone and makes the swipe action trivially testable with a
// recording fake.
public protocol OutboxEnqueuing: Sendable {
    func enqueue(_ payload: OutboxPayload) async throws
}
