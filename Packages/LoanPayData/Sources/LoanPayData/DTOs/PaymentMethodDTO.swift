import Foundation
import LoanPayDomain

struct PaymentMethodDTO: Decodable {
    let id: String
    let displayName: String
    let kind: String

    func toDomain() throws -> PaymentMethod {
        PaymentMethod(
            id: PaymentMethodID(id),
            displayName: displayName,
            // WHY not `.unknown` here: an unrecognized payment method is not
            // like an unrecognized loan status. Showing a method we cannot
            // execute invites a failed payment, so unknown kinds are a
            // decode error, not a degraded row.
            kind: try PaymentMethod.Kind(rawValue: kind)
                .unwrapOrThrow(DomainError.invalidData(keyPath: "payment_method.kind"))
        )
    }
}

extension Optional {
    // LANG: a tiny extension beats `guard let` boilerplate at every mapper
    // call site; it keeps the throwing path visible in one expression.
    func unwrapOrThrow(_ error: @autoclosure () -> DomainError) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}
