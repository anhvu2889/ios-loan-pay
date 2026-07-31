import Foundation
import LoanPayDomain

/// `PaymentRepository` over the reference HTTP client.
public struct RemotePaymentRepository: PaymentRepository {
    private struct PaymentBody: Encodable {
        let loanId: String
        let methodId: String
        let amount: String
        let idempotencyKey: String
    }

    private struct PaymentEchoDTO: Decodable {
        let id: String
    }

    private let client: URLSessionAPIClient

    public init(client: URLSessionAPIClient) {
        self.client = client
    }

    public func fetchPaymentMethods(for loanID: LoanID) async throws -> [PaymentMethod] {
        try await ErrorMapper.mapping {
            let dtos: [PaymentMethodDTO] = try await client.get("payment-methods")
            return try dtos.map { try $0.toDomain() }
        }
    }

    public func submit(_ request: PaymentRequest) async throws -> PaymentReceipt {
        try await ErrorMapper.mapping {
            let body = PaymentBody(
                loanId: request.loanID.rawValue,
                methodId: request.methodID.rawValue,
                // FINTECH: the amount goes out as a STRING, same rule as
                // inbound — a JSON number would round-trip through Double
                // somewhere between here and the ledger.
                amount: "\(request.amount.amount)",
                idempotencyKey: request.idempotencyKey.value
            )
            // The key rides BOTH the header (transport-level dedupe) and
            // the body (json-server persists it, so replays are visible in
            // db.json during development).
            let echo: PaymentEchoDTO = try await client.post(
                "payments",
                body: body,
                idempotencyKey: request.idempotencyKey
            )

            // json-server echoes the created record; a real payments API
            // returns a receipt with the authoritative remaining balance.
            // Re-reading the loan keeps this reference path honest instead
            // of inventing a number.
            let loan: LoanDTO = try await client.get("loans/\(request.loanID.rawValue)")
            let outstanding = try WireAmount.decimal(
                loan.outstandingBalance,
                keyPath: "loan.outstanding_balance"
            )
            return PaymentReceipt(
                paymentID: echo.id,
                loanID: request.loanID,
                amountPaid: request.amount,
                remainingBalance: Money(
                    amount: max(0, outstanding - request.amount.amount),
                    currencyCode: request.amount.currencyCode
                ),
                processedAt: Date()
            )
        }
    }
}
