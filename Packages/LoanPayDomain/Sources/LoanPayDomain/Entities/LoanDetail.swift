import Foundation

/// Everything the detail screen and payment flow need about one loan:
/// the summary plus the full installment book and balance history.
public struct LoanDetail: Hashable, Sendable, Identifiable {
    public let loan: Loan
    public let startDate: Date
    public let installments: [Installment]
    public let balanceHistory: [BalancePoint]

    public var id: LoanID { loan.id }

    public init(
        loan: Loan,
        startDate: Date,
        installments: [Installment],
        balanceHistory: [BalancePoint]
    ) {
        self.loan = loan
        self.startDate = startDate
        self.installments = installments
        self.balanceHistory = balanceHistory
    }
}
