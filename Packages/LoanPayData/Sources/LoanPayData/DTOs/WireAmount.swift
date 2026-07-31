import Foundation
import LoanPayDomain

// FINTECH: amounts travel the wire as STRINGS ("125.50"), never JSON
// numbers. A JSON number is decoded through Double on its way to anything
// else, and the value is corrupted before application code ever sees it.
// This is the single place a wire string becomes a Decimal.
enum WireAmount {
    static func decimal(_ string: String, keyPath: String) throws -> Decimal {
        // FINTECH: Decimal(string:) is a PREFIX parser — "14o.50" quietly
        // parses as 14, truncating a corrupt amount instead of rejecting it.
        // For money, silent truncation is worse than failure, so the wire
        // string must match the strict amount grammar before parsing.
        guard string.wholeMatch(of: /-?[0-9]+(?:\.[0-9]+)?/) != nil,
              // LANG: the POSIX locale is not a nicety. Decimal(string:)
              // honors the locale's decimal separator, so on a comma-decimal
              // device ("vi_VN", "de_DE") parsing "125.50" without pinning
              // the locale yields 12550 — a 100x balance error from a
              // formatting default.
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            // FINTECH: the error names the FIELD, never the value — the
            // malformed payload may contain a borrower's balance.
            throw DomainError.invalidData(keyPath: keyPath)
        }
        return value
    }
}
