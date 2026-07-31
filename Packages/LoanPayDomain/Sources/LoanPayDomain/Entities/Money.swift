import Foundation

// FINTECH: Money is `Decimal` and nothing else. Binary floating point cannot
// represent most decimal fractions: 0.1 + 0.2 == 0.30000000000000004 in
// Double, and an installment book that drifts by fractions of a cent is a
// reconciliation incident, not a rounding nicety. Decimal stores base-10
// significands, so 0.10 + 0.20 is exactly 0.30. The wire format sends
// amounts as *strings* for the same reason — a JSON number decoded into
// Double corrupts the value before our code ever sees it.
public struct Money: Hashable, Sendable, Codable {
    public let amount: Decimal
    public let currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    public static func zero(currencyCode: String) -> Money {
        Money(amount: 0, currencyCode: currencyCode)
    }

    // FINTECH: Addition is throwing, not silent. Summing 500 USD and 500 KES
    // as "1000" is exactly the kind of quiet corruption a lender cannot
    // afford, so mixing currencies refuses loudly instead of guessing an
    // exchange rate. The keyPath in the error names the offending field
    // without leaking the amounts themselves.
    public func adding(_ other: Money) throws -> Money {
        guard other.currencyCode == currencyCode else {
            throw DomainError.invalidData(keyPath: "Money.currencyCode")
        }
        return Money(amount: amount + other.amount, currencyCode: currencyCode)
    }

    public static func sum(_ values: [Money], currencyCode: String) throws -> Money {
        try values.reduce(.zero(currencyCode: currencyCode)) { try $0.adding($1) }
    }

    // MODERN: FormatStyle (iOS 15+) replaces the old NumberFormatter dance —
    // no mutable formatter object to configure, cache and keep thread-safe;
    // the style is a value and the call site reads declaratively.
    // LANG: locale is a defaulted parameter, not a hard-coded value, so
    // production renders in the user's locale while tests pin en_US and can
    // assert exact strings on any machine.
    public func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    // FINTECH: The single spoken form for every amount in the app. VoiceOver
    // reading "$1,250.00" digit-by-digit ("dollar one comma two five zero…")
    // is unusable; `.presentation(.fullName)` yields "1,250.00 US dollars".
    // Accessibility labels must use this, never `formatted(locale:)`.
    public func spokenDescription(locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.currency(code: currencyCode).presentation(.fullName).locale(locale))
    }
}
