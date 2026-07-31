import Foundation
import Observation
import LoanPayDomain
import LoanPayFeatureKit

/// Owns the root navigation path, modal presentation, and the deferred
/// destination that survives the login wall.
///
/// ARCH: screens never push; they ask the coordinator. A ViewModel that
/// appends to a NavigationPath it also renders becomes untestable and
/// unshareable; a coordinator that owns `[AppRoute]` can be driven and
/// asserted in a unit test with no UI attached.
///
/// WHY a typed `[AppRoute]` and not NavigationPath: NavigationPath is
/// opaque — you can count it, you cannot READ it. Every method below
/// (unwind(to:), "is the confirmation reachable?") requires reading the
/// stack; type-erasing the path would make this entire API unimplementable.
@Observable
@MainActor
final class AppCoordinator {
    // LANG: `private(set)` + mutating methods instead of a public var:
    // every path change goes through a named intent, which is what keeps
    // "who navigated and why" greppable. The binding SwiftUI needs is
    // exposed separately below.
    private(set) var path: [AppRoute] = []

    /// The loan a payment sheet is presented for, if any. Presentation
    /// lives HERE (not in view @State) so `dismissAllAndUnwind` can be a
    /// real, testable operation instead of scattered view bookkeeping.
    private(set) var presentedPaymentLoanID: LoanID?

    private let logger: any AppLogger

    init(logger: any AppLogger) {
        self.logger = logger
    }

    // MARK: - Forward navigation

    func show(_ route: AppRoute) {
        path.append(route)
    }

    func presentPayment(for loanID: LoanID) {
        presentedPaymentLoanID = loanID
    }

    func dismissPayment() {
        presentedPaymentLoanID = nil
    }

    // MARK: - Unwind API

    func popLast(_ count: Int = 1) {
        path.removeLast(min(count, path.count))
    }

    /// Unwinds so `route` is topmost. Missing target → root, loudly.
    ///
    /// WHY root and not no-op on a missing target: the caller believed a
    /// screen was on the stack and it is not — state has diverged. Root is
    /// the only destination that is ALWAYS valid; staying put would leave
    /// the user on a screen the caller thinks is gone. The warning makes
    /// the divergence countable in the field.
    func unwind(to route: AppRoute) {
        guard let index = path.lastIndex(of: route) else {
            logger.log(.warning, category: .ui, "unwind target missing from path; falling back to root")
            path.removeAll()
            return
        }
        path.removeLast(path.count - index - 1)
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Tears down modals FIRST, then unwinds — the order matters, because
    /// unwinding beneath a live payment sheet would change what the sheet
    /// returns to mid-flight.
    func dismissAllAndUnwind(to route: AppRoute?) {
        presentedPaymentLoanID = nil
        if let route {
            unwind(to: route)
        } else {
            path.removeAll()
        }
    }

    /// NavigationStack needs a read-write binding (back gestures pop the
    /// path from the UI side). Routing it through this accessor keeps
    /// `path` writes inside the coordinator's file.
    var pathBinding: [AppRoute] {
        get { path }
        set { path = newValue }
    }

    // MARK: - Pending destination

    /// Where the user was headed when authentication interrupted them.
    ///
    /// FINTECH: a deep link to a guarded screen must SURVIVE the login wall
    /// — "tap the payment reminder, sign in, land on the loan" — but it
    /// must fire at most once. A pending intent that replayed on every auth
    /// transition would re-open payment screens on session refreshes.
    private(set) var pendingIntent: NavigationIntent?

    func deferUntilAuthenticated(_ intent: NavigationIntent) {
        pendingIntent = intent
    }

    /// Returns the stored intent and CLEARS it — consume-once is the
    /// contract, enforced structurally rather than by caller discipline.
    func consumePendingIntent() -> NavigationIntent? {
        defer { pendingIntent = nil }
        return pendingIntent
    }

    // MARK: - Applying intents

    /// Makes the app look the way the intent describes: modals down, base
    /// context assumed, routes replaced, payment sheet up last.
    func apply(_ intent: NavigationIntent) {
        presentedPaymentLoanID = nil
        switch intent.base {
        case .loanList:
            path = intent.routes
        }
        if let loanID = intent.paymentForLoanID {
            presentedPaymentLoanID = loanID
        }
    }
}
