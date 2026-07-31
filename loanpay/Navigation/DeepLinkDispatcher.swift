import Foundation
import LoanPayDomain
import LoanPayFeatureKit

/// Routes incoming URLs to feature handlers.
///
/// ARCH: this type knows NOTHING about any feature's URL grammar. It owns
/// exactly one thing — the prefix table `featureID → handler` — populated
/// at startup from feature registrations. `loanpay://payment/...` goes to
/// whatever registered "payment"; what the rest of the URL means is that
/// feature's private business.
@MainActor
final class DeepLinkDispatcher {
    private var handlers: [String: any DeepLinkHandling] = [:]
    private let logger: any AppLogger

    init(logger: any AppLogger) {
        self.logger = logger
    }

    func register(featureID: String, handler: any DeepLinkHandling) {
        // Double registration is a wiring bug worth hearing about in DEBUG,
        // but never worth crashing production composition over.
        if handlers[featureID] != nil {
            logger.log(.warning, category: .ui, "duplicate deep-link registration for a feature id")
        }
        handlers[featureID] = handler
    }

    /// Returns what should happen, or nil for "dropped".
    ///
    /// WHY dropped links return nil instead of throwing: an unparseable
    /// link is hostile-or-broken INPUT, not a program error. The contract
    /// is: log the shape (never the payload — it is untrusted and may be
    /// crafted to poison logs), do nothing visible, move on.
    func dispatch(_ url: URL, isAuthenticated: Bool) -> DeepLinkOutcome? {
        guard url.scheme == "loanpay", let featureID = url.host() else {
            logger.log(.warning, category: .ui, "deep link dropped: wrong scheme or missing feature prefix")
            return nil
        }
        guard let handler = handlers[featureID] else {
            logger.log(.warning, category: .ui, "deep link dropped: no handler registered for prefix")
            return nil
        }

        // WHY reject empty segments explicitly: Foundation COLLAPSES "//"
        // when splitting paths, so "payment//methods" would silently parse
        // as a one-segment link with loan id "methods". A link containing
        // an empty segment is malformed, not creatively spelled.
        guard !url.path().contains("//") else {
            logger.log(.warning, category: .ui, "deep link dropped: empty path segment")
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        let outcome = handler.handle(pathComponents: components, isAuthenticated: isAuthenticated)

        if outcome == .notRecognized {
            logger.log(.warning, category: .ui, "deep link dropped: feature did not recognize path shape")
            return nil
        }
        return outcome
    }
}
