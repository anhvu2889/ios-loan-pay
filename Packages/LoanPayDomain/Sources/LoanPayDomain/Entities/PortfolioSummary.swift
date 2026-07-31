import Foundation

/// Aggregated payoff position across the visible portfolio.
///
/// FINTECH: a summary built from per-loan quotes can be *partial* — some
/// quotes may have failed. Rather than hiding that, the summary carries
/// exactly which loans made it in and which did not, so the UI can label the
/// figure as incomplete. A total that silently omits loans reads as "you owe
/// less than you do", which is the one direction a lender must never err in.
public struct PortfolioSummary: Hashable, Sendable {
    public let totalOutstanding: Money
    public let overdueLoanCount: Int
    /// Loan ids whose quotes are included, in the caller's original order.
    public let includedLoanIDs: [LoanID]
    /// Loan ids whose quotes failed and are missing from the total.
    public let failedLoanIDs: [LoanID]

    public var isComplete: Bool { failedLoanIDs.isEmpty }

    public init(
        totalOutstanding: Money,
        overdueLoanCount: Int,
        includedLoanIDs: [LoanID],
        failedLoanIDs: [LoanID]
    ) {
        self.totalOutstanding = totalOutstanding
        self.overdueLoanCount = overdueLoanCount
        self.includedLoanIDs = includedLoanIDs
        self.failedLoanIDs = failedLoanIDs
    }
}
