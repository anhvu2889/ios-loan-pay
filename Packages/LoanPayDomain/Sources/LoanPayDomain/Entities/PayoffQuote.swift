import Foundation

// FINTECH: The exact amount to settle a loan today is computed server-side
// (accrued interest, penalties, waivers) and is only valid at `asOf`. The
// client never derives payoff amounts from installment arithmetic — a stale
// or locally-recomputed figure shown to a borrower is a dispute waiting to
// happen. Portfolio totals are aggregated from these quotes.
public struct PayoffQuote: Hashable, Sendable {
    public let loanID: LoanID
    public let amount: Money
    public let asOf: Date

    public init(loanID: LoanID, amount: Money, asOf: Date) {
        self.loanID = loanID
        self.amount = amount
        self.asOf = asOf
    }
}
