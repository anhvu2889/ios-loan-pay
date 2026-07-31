import Foundation

public protocol PaymentRepository: Sendable {
    func fetchPaymentMethods(for loanID: LoanID) async throws -> [PaymentMethod]

    // FINTECH: `submit` must be treated as at-most-once-visible, not
    // at-most-once-executed: a thrown timeout does NOT mean the payment
    // failed — it may have landed. That is why the request carries an
    // idempotency key and why callers never auto-retry this method; only a
    // human, resubmitting with the SAME key, may try again.
    func submit(_ request: PaymentRequest) async throws -> PaymentReceipt
}
