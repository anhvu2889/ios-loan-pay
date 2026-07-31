import Foundation
import LoanPayDomain

/// What a deep link WANTS to happen, expressed declaratively.
///
/// ARCH: a deep link handler never navigates — it returns one of these and
/// the app's coordinator applies it. That split is what makes "does
/// loanpay://payment/x/methods parse correctly?" a pure unit test with no
/// UI, and what lets the same intent be stored untouched while the user
/// detours through login.
public struct NavigationIntent: Equatable, Sendable {
    /// The context the intent needs underneath it. Declaring it (rather
    /// than assuming "whatever is on screen") is what lets the coordinator
    /// rebuild a sane stack when the link arrives mid-flow.
    public enum BaseContext: Equatable, Sendable {
        case loanList
    }

    public let base: BaseContext
    /// Routes pushed on top of the base, in order.
    public let routes: [AppRoute]
    /// A payment sheet presented on top of the final route, if any.
    public let paymentForLoanID: LoanID?

    public init(base: BaseContext = .loanList, routes: [AppRoute] = [], paymentForLoanID: LoanID? = nil) {
        self.base = base
        self.routes = routes
        self.paymentForLoanID = paymentForLoanID
    }
}
