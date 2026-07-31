import Foundation
import Testing
import LoanPayDomain

@Suite struct MoneyTests {
    @Test func decimalAdditionIsExact() throws {
        let sum = try Money.usd("0.10").adding(.usd("0.20"))
        #expect(sum == .usd("0.30"))
        // The same assertion on Double fails — this is the whole reason
        // Money is Decimal-only:
        //   let d: Double = 0.1 + 0.2
        //   d == 0.3            // false: d is 0.30000000000000004
        // Binary floating point cannot represent 0.1 or 0.2 exactly, so the
        // error compounds across an installment book. Decimal stores base-10
        // significands and adds exactly.
    }

    @Test func mixedCurrencyAdditionRefuses() {
        let kes = Money(amount: 100, currencyCode: "KES")
        #expect(throws: DomainError.invalidData(keyPath: "Money.currencyCode")) {
            _ = try Money.usd("1.00").adding(kes)
        }
    }

    @Test func sumPreservesExactness() throws {
        let total = try Money.sum(
            [.usd("0.10"), .usd("0.20"), .usd("1234.56")],
            currencyCode: "USD"
        )
        #expect(total == .usd("1234.86"))
    }

    @Test func sumOfNothingIsZero() throws {
        let total = try Money.sum([], currencyCode: "USD")
        #expect(total == .zero(currencyCode: "USD"))
    }

    @Test func formattedRendersCurrencySymbol() {
        let formatted = Money.usd("1250.50").formatted(locale: Locale(identifier: "en_US"))
        #expect(formatted == "$1,250.50")
    }

    @Test func spokenDescriptionSpeaksUnitsNotDigits() {
        let spoken = Money.usd("1250.50").spokenDescription(locale: Locale(identifier: "en_US"))
        #expect(spoken.contains("US dollars"))
        #expect(!spoken.contains("$"))
    }
}
