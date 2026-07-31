import Foundation
import LoanPayDomain

/// Flags for previews and feature-package tests: everything on unless the
/// preview turns something off to show that state.
public struct PreviewFeatureFlags: FeatureFlags {
    private let disabled: Set<FeatureFlag>

    public init(disabled: Set<FeatureFlag> = []) {
        self.disabled = disabled
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        !disabled.contains(flag)
    }
}
