import Foundation

// FINTECH: The outbox NEVER carries money. Deferred, replayed-later requests
// are fine for "call me back about my loan"; they are catastrophic for
// payments, where the user must be present to see the outcome (success,
// declined, session expired) and decide what happens next. If a case with an
// amount ever appears here, that is a design regression, not an extension.
public enum OutboxPayload: Codable, Hashable, Sendable {
    case supportCallback(topic: String, loanID: LoanID?)
}
