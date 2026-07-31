import Foundation

// ARCH: the dispatcher owns ONLY a prefix table (featureID → handler);
// everything after the prefix is the feature's private grammar. Features
// can add, rename or restructure their internal routes without the app
// target knowing — the alternative, one central URL parser, turns every
// feature change into an app-level edit and merge conflict.
public protocol DeepLinkHandling: Sendable {
    /// - Parameter pathComponents: the URL's path segments AFTER the
    ///   feature prefix (for `loanpay://payment/loan-1/methods` the payment
    ///   handler receives `["loan-1", "methods"]`).
    /// - Parameter isAuthenticated: lets the handler decide between
    ///   `.handled` and `.requiresAuth` — guarded-ness is the feature's
    ///   knowledge, not the dispatcher's.
    func handle(pathComponents: [String], isAuthenticated: Bool) -> DeepLinkOutcome
}
