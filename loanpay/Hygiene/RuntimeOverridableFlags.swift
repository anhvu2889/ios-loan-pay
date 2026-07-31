import Foundation
import LoanPayDomain

/// Wraps any `FeatureFlags` source with runtime overrides — the debug
/// menu's flag toggles write here, so a tester can flip the payments kill
/// switch without editing the bundle.
///
/// LANG: `@unchecked Sendable` + NSLock instead of an actor because
/// `isEnabled` must stay SYNCHRONOUS — it is consulted inside view bodies,
/// where an `await` is impossible. The lock's critical sections are
/// dictionary reads/writes only; the unchecked promise is kept by never
/// touching `overrides` outside `withLock`.
final class RuntimeOverridableFlags: FeatureFlags, @unchecked Sendable {
    private let base: any FeatureFlags
    private let lock = NSLock()
    private var overrides: [FeatureFlag: Bool] = [:]

    init(base: any FeatureFlags) {
        self.base = base
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        lock.withLock {
            overrides[flag]
        } ?? base.isEnabled(flag)
    }

    func setOverride(_ value: Bool?, for flag: FeatureFlag) {
        lock.withLock {
            overrides[flag] = value
        }
    }

    func override(for flag: FeatureFlag) -> Bool? {
        lock.withLock {
            overrides[flag]
        }
    }
}
