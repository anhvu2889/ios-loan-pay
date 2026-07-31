import Foundation

public struct PaymentReceipt: Hashable, Sendable {
    /// Server-assigned identifier of the settled payment.
    public let paymentID: String
    public let loanID: LoanID
    public let amountPaid: Money
    public let remainingBalance: Money
    public let processedAt: Date

    public init(
        paymentID: String,
        loanID: LoanID,
        amountPaid: Money,
        remainingBalance: Money,
        processedAt: Date
    ) {
        self.paymentID = paymentID
        self.loanID = loanID
        self.amountPaid = amountPaid
        self.remainingBalance = remainingBalance
        self.processedAt = processedAt
    }
}
