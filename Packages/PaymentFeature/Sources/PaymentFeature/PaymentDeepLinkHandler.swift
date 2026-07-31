import Foundation
import LoanPayDomain
import LoanPayFeatureKit

/// Grammar: `payment/<loanId>` and `payment/<loanId>/methods`.
/// Both land on the loan's detail with the payment sheet on top — the
/// sheet's first screen IS the methods screen, so the longer form is an
/// alias kept for notification templates.
public struct PaymentDeepLinkHandler: DeepLinkHandling {
    public init() {}

    public func handle(pathComponents: [String], isAuthenticated: Bool) -> DeepLinkOutcome {
        guard let rawID = pathComponents.first,
              let loanID = DeepLinkParameter.identifier(rawID).map(LoanID.init) else {
            return .notRecognized
        }
        switch pathComponents.count {
        case 1:
            break
        case 2 where pathComponents[1] == "methods":
            break
        default:
            return .notRecognized
        }

        let intent = NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(loanID)],
            paymentForLoanID: loanID
        )
        // FINTECH: a payment surface behind a cold start is ALWAYS guarded.
        // The intent survives the login+biometric detour verbatim; what
        // must not survive is any assumption that the tapper is the owner.
        return isAuthenticated ? .handled(intent) : .requiresAuth(intent)
    }
}
