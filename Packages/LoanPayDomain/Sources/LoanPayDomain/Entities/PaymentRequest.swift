import Foundation

public struct PaymentRequest: Hashable, Sendable {
    public let loanID: LoanID
    public let methodID: PaymentMethodID
    public let amount: Money
    public let idempotencyKey: IdempotencyKey

    public init(
        loanID: LoanID,
        methodID: PaymentMethodID,
        amount: Money,
        idempotencyKey: IdempotencyKey
    ) {
        self.loanID = loanID
        self.methodID = methodID
        self.amount = amount
        self.idempotencyKey = idempotencyKey
    }
}
