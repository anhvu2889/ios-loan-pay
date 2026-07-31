import Foundation

// FINTECH: The idempotency key is the only thing standing between "the
// request timed out" and "the borrower was charged twice". The client mints
// one key per *payment intent* (not per HTTP attempt): a retry after a
// timeout must resend the SAME bytes so the server can recognize the
// duplicate and return the original result instead of charging again. A new
// key is minted only when the user starts a genuinely new payment.
public struct IdempotencyKey: Hashable, Sendable, Codable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> IdempotencyKey {
        IdempotencyKey(value: UUID().uuidString)
    }
}
