import Foundation

// LANG: raw values are the wire/config names, kept lowercase_snake to match
// the flags.json inventory; the enum cases are the only way code can spell a
// flag, so a typo'd flag name cannot compile.
public enum FeatureFlag: String, CaseIterable, Sendable {
    /// Gates the loan-list search UI while the ranking work is validated.
    case search = "search_enabled"
    // FINTECH: the payments kill switch. When off, the payment flow renders
    // a maintenance state and `.pay` is a no-op — the fastest possible
    // remote mitigation when a payments provider melts down. This flag is
    // permanent by design; feature flags around it come and go.
    case paymentsEnabled = "payments_enabled"
}

public protocol FeatureFlags: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
}
