import Foundation

/// One page of the loan list.
public struct LoanPage: Hashable, Sendable {
    /// 1-based page index as served; page 1 is the initial load.
    public let index: Int
    public let loans: [Loan]
    public let hasMore: Bool

    public init(index: Int, loans: [Loan], hasMore: Bool) {
        self.index = index
        self.loans = loans
        self.hasMore = hasMore
    }
}
