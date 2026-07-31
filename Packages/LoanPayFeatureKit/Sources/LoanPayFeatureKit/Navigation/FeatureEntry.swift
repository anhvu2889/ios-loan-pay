import Foundation

// ARCH: a feature package exposes exactly ONE public type — its entry —
// and the app composes features by registering entries, never by reaching
// into feature internals. Whatever a feature contributes to app-level
// concerns (deep links, debug menu sections, flag inventories) hangs off
// this protocol, so adding a feature never edits app code beyond one
// `register` call.
public protocol FeatureEntry: Sendable {
    /// Stable identity; doubles as the feature's deep-link path prefix
    /// (e.g. "loans" handles loanpay://loans/...).
    static var featureID: String { get }
}
