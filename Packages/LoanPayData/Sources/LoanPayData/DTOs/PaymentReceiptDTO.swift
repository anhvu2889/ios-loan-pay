import Foundation
import LoanPayDomain

struct PaymentReceiptDTO: Decodable {
    let paymentId: String
    let loanId: String
    let amountPaid: String
    let remainingBalance: String
    let processedAt: Date

    func toDomain() throws -> PaymentReceipt {
        PaymentReceipt(
            paymentID: paymentId,
            loanID: LoanID(loanId),
            amountPaid: Money(
                amount: try WireAmount.decimal(amountPaid, keyPath: "receipt.amount_paid"),
                currencyCode: "USD"
            ),
            remainingBalance: Money(
                amount: try WireAmount.decimal(remainingBalance, keyPath: "receipt.remaining_balance"),
                currencyCode: "USD"
            ),
            processedAt: processedAt
        )
    }
}
