import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct LoanDTOMappingTests {
    private func decodeLoan(_ json: String) throws -> LoanDTO {
        try MockFixtures.makeDecoder().decode(LoanDTO.self, from: Data(json.utf8))
    }

    private let validJSON = """
    {
      "id": "loan-9",
      "device_model": "Galaxy A15",
      "device_image_url": "https://example.com/a15.png",
      "principal": "240.00",
      "outstanding_balance": "140.50",
      "monthly_installment": "20.00",
      "status": "active",
      "next_installment_due": "2026-08-10T00:00:00Z"
    }
    """

    @Test func wireStringsBecomeExactDecimals() throws {
        let loan = try decodeLoan(validJSON).toDomain()
        #expect(loan.outstandingBalance == Money(amount: Decimal(string: "140.50")!, currencyCode: "USD"))
        #expect(loan.principal.amount == 240)
        #expect(loan.status == .active)
        #expect(loan.id == LoanID("loan-9"))
        #expect(loan.deviceImageURL?.absoluteString == "https://example.com/a15.png")
    }

    @Test func malformedAmountThrowsInvalidDataNamingTheField() throws {
        let dto = try decodeLoan(validJSON.replacingOccurrences(of: "\"140.50\"", with: "\"14o.50\""))
        #expect(throws: DomainError.invalidData(keyPath: "loan.outstanding_balance")) {
            _ = try dto.toDomain()
        }
    }

    @Test func unknownStatusFallsBackInsteadOfFailing() throws {
        let dto = try decodeLoan(validJSON.replacingOccurrences(of: "\"active\"", with: "\"restructured\""))
        // FINTECH: forward compatibility — the loan still renders; it must
        // never vanish because the server learned a new word.
        #expect(try dto.toDomain().status == .unknown)
    }

    @Test func missingDueDateMapsToNil() throws {
        let dto = try decodeLoan(validJSON.replacingOccurrences(
            of: "\"2026-08-10T00:00:00Z\"",
            with: "null"
        ))
        #expect(try dto.toDomain().nextInstallmentDue == nil)
    }

    @Test func unknownPaymentMethodKindRefusesToDecode() throws {
        let dto = try MockFixtures.makeDecoder().decode(
            PaymentMethodDTO.self,
            from: Data(#"{"id": "pm-1", "display_name": "Crypto", "kind": "cryptoWallet"}"#.utf8)
        )
        #expect(throws: DomainError.invalidData(keyPath: "payment_method.kind")) {
            _ = try dto.toDomain()
        }
    }
}
