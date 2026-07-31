import Foundation
import LoanPayDomain

/// Wire shape of one loan as the API serves it. Mirrors the JSON exactly —
/// amounts are strings, dates are ISO 8601, and nothing here is a domain
/// type. The `toDomain()` mapper is the only exit.
struct LoanDTO: Decodable {
    let id: String
    let deviceModel: String
    let deviceImageUrl: String?
    let principal: String
    let outstandingBalance: String
    let monthlyInstallment: String
    let status: String
    let nextInstallmentDue: Date?

    // ARCH: DTO → entity is a *throwing translation*, not a cast. Malformed
    // amounts surface as DomainError.invalidData with the offending key
    // path; unknown statuses degrade to `.unknown` instead of failing —
    // one is data corruption (refuse), the other is forward compatibility
    // (tolerate). The distinction is the whole point of a mapper.
    func toDomain() throws -> Loan {
        let currency = "USD"
        return Loan(
            id: LoanID(id),
            deviceModel: deviceModel,
            deviceImageURL: deviceImageUrl.flatMap(URL.init(string:)),
            principal: Money(
                amount: try WireAmount.decimal(principal, keyPath: "loan.principal"),
                currencyCode: currency
            ),
            outstandingBalance: Money(
                amount: try WireAmount.decimal(outstandingBalance, keyPath: "loan.outstanding_balance"),
                currencyCode: currency
            ),
            monthlyInstallment: Money(
                amount: try WireAmount.decimal(monthlyInstallment, keyPath: "loan.monthly_installment"),
                currencyCode: currency
            ),
            status: LoanStatus(rawValue: status) ?? .unknown,
            nextInstallmentDue: nextInstallmentDue
        )
    }
}
