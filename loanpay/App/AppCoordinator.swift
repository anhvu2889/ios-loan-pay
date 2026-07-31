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

    /// NavigationStack needs a read-write binding (back gestures pop the
    /// path from the UI side). Routing it through this accessor keeps
    /// `path` writes inside the coordinator's file.
    var pathBinding: [AppRoute] {
        get { path }
        set { path = newValue }
    }
}
