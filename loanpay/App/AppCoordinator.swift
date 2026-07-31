import Foundation
import Observation
import LoanPayFeatureKit

/// Owns the root navigation path.
///
/// ARCH: screens never push; they ask the coordinator. A ViewModel that
/// appends to a NavigationPath it also renders becomes untestable and
/// unshareable; a coordinator that owns `[AppRoute]` can be driven and
/// asserted in a unit test with no UI attached.
///
/// LANG: `private(set)` + mutating methods instead of a public var: every
/// path change goes through a named intent (`show`, `pop…`), which is what
/// keeps "who navigated and why" greppable. The binding SwiftUI needs is
/// exposed separately below.
@Observable
@MainActor
final class AppCoordinator {
    private(set) var path: [AppRoute] = []

    func show(_ route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }

    // MARK: - Pending destination

    /// Where the user was headed when authentication interrupted them.
    ///
    /// FINTECH: a deep link to a guarded screen must SURVIVE the login wall
    /// — "tap the payment reminder, sign in, land on the loan" — but it
    /// must fire at most once. A pending destination that replays on every
    /// auth transition would re-open payment screens on session refreshes.
    private(set) var pendingDestination: AppRoute?

    func deferUntilAuthenticated(_ route: AppRoute) {
        pendingDestination = route
    }

    /// Returns the stored destination and CLEARS it — consume-once is the
    /// contract, enforced structurally rather than by caller discipline.
    func consumePendingDestination() -> AppRoute? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    /// NavigationStack needs a read-write binding (back gestures pop the
    /// path from the UI side). Routing it through this accessor keeps
    /// `path` writes inside the coordinator's file.
    var pathBinding: [AppRoute] {
        get { path }
        set { path = newValue }
    }
}
