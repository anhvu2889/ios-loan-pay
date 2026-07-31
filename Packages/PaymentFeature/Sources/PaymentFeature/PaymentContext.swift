import Foundation
import LoanPayDomain

/// Everything the payment screen needs, loaded up front as one unit.
public struct PaymentContext: Equatable, Sendable {
    public let detail: LoanDetail
    public let methods: [PaymentMethod]
    public var selectedMethodID: PaymentMethodID?

    /// What this payment pays: the monthly installment, capped at the
    /// remaining balance for the final payment.
    ///
    /// FINTECH: the amount is DERIVED, not typed. Free-amount entry is a
    /// deliberate non-feature here — partial payments have server-side
    /// allocation rules (fees first? principal first?) that the client
    /// must not guess at.
    public var amount: Money {
        let monthly = detail.loan.monthlyInstallment
        let outstanding = detail.loan.outstandingBalance
        return outstanding.amount < monthly.amount ? outstanding : monthly
    }

    public var selectedMethod: PaymentMethod? {
        methods.first { $0.id == selectedMethodID }
    }

    public init(detail: LoanDetail, methods: [PaymentMethod], selectedMethodID: PaymentMethodID? = nil) {
        self.detail = detail
        self.methods = methods
        // WHY preselect the first method: one fewer decision on the hot
        // path; the picker remains for switching.
        self.selectedMethodID = selectedMethodID ?? methods.first?.id
    }
}
