import Foundation
import LoanPayDomain

/// Mock payment rail. Deliberately simulates the server-side half of the
/// idempotency contract, because the client-side half (key reuse) is only
/// meaningful against a server that honors it.
///
/// LANG: an actor because `settledByKey` is mutated across concurrent
/// submissions; the compiler serializes access so a double-submit race
/// cannot corrupt the ledger even in the mock.
public actor MockPaymentRepository: PaymentRepository {
    private let behavior: MockBehavior
    private let sleeper: any Sleeper
    /// The mock server's dedupe ledger: idempotency key → the receipt that
    /// was minted the first time that key settled.
    private var settledByKey: [IdempotencyKey: PaymentReceipt] = [:]

    public init(behavior: MockBehavior, sleeper: any Sleeper = ContinuousSleeper()) {
        self.behavior = behavior
        self.sleeper = sleeper
    }

    public func fetchPaymentMethods(for loanID: LoanID) async throws -> [PaymentMethod] {
        try await ErrorMapper.mapping {
            _ = try await behavior.preflight(.paymentMethods, sleeper: sleeper)
            let data = try MockFixtures.data(named: "payment-methods")
            return try MockFixtures.makeDecoder()
                .decode([PaymentMethodDTO].self, from: data)
                .map { try $0.toDomain() }
        }
    }

    public func submit(_ request: PaymentRequest) async throws -> PaymentReceipt {
        try await ErrorMapper.mapping {
            // FINTECH: the dedupe check runs BEFORE failure injection so a
            // replayed key returns the original receipt even while the
            // endpoint is failing — mirroring a real idempotent server,
            // where the first request may have settled although the client
            // only ever saw a timeout.
            if let settled = settledByKey[request.idempotencyKey] {
                return settled
            }

            _ = try await behavior.preflight(.submitPayment, sleeper: sleeper)

            let loans = try MockFixtures.makeDecoder()
                .decode([LoanDTO].self, from: MockFixtures.data(named: "loans"))
            guard let dto = loans.first(where: { $0.id == request.loanID.rawValue }) else {
                throw HTTPError(statusCode: 404)
            }
            let outstanding = try WireAmount.decimal(
                dto.outstandingBalance,
                keyPath: "loan.outstanding_balance"
            )
            let remaining = max(0, outstanding - request.amount.amount)

            let receipt = PaymentReceipt(
                // Deterministic from the key: replaying the same intent can
                // never mint a second payment id.
                paymentID: "pay-\(request.idempotencyKey.value.prefix(8))",
                loanID: request.loanID,
                amountPaid: request.amount,
                remainingBalance: Money(amount: remaining, currencyCode: request.amount.currencyCode),
                processedAt: Date()
            )
            settledByKey[request.idempotencyKey] = receipt
            return receipt
        }
    }
}
