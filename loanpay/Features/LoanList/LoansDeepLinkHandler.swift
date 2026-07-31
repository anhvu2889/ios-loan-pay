import Foundation
import LoanPayDomain
import LoanPayFeatureKit

/// Grammar: `loans` (the list) and `loans/<loanId>` (one loan's detail).
struct LoansDeepLinkHandler: DeepLinkHandling {
    func handle(pathComponents: [String], isAuthenticated: Bool) -> DeepLinkOutcome {
        let intent: NavigationIntent
        switch pathComponents.count {
        case 0:
            intent = NavigationIntent(base: .loanList)
        case 1:
            guard let loanID = DeepLinkParameter.identifier(pathComponents[0]).map(LoanID.init) else {
                return .notRecognized
            }
            intent = NavigationIntent(base: .loanList, routes: [.loanDetail(loanID)])
        default:
            return .notRecognized
        }
        // Everything in this app is behind the wall; the distinction the
        // outcome carries is WHICH side of it the user is currently on.
        return isAuthenticated ? .handled(intent) : .requiresAuth(intent)
    }
}
