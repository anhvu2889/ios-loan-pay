import Foundation
import LoanPayFeatureKit

/// Grammar: `support/callback` and `support/callback/<topic>`.
public struct SupportDeepLinkHandler: DeepLinkHandling {
    public init() {}

    public func handle(pathComponents: [String], isAuthenticated: Bool) -> DeepLinkOutcome {
        guard pathComponents.first == "callback" else { return .notRecognized }

        let topic: String?
        switch pathComponents.count {
        case 1:
            topic = nil
        case 2:
            // Topics ride the same strict identifier validation as ids —
            // they end up in a queued payload, so garbage stops here.
            guard let validated = DeepLinkParameter.identifier(pathComponents[1]) else {
                return .notRecognized
            }
            topic = validated
        default:
            return .notRecognized
        }

        let intent = NavigationIntent(base: .loanList, routes: [.supportCallback(topic: topic)])
        return isAuthenticated ? .handled(intent) : .requiresAuth(intent)
    }
}
