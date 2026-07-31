import Foundation
import Testing
import LoanPayDomain
import LoanPayFeatureKit
@testable import loanpay

/// Records warnings so "missing unwind target logs" is assertable.
final class RecordingLogger: AppLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var _warnings: [String] = []

    var warnings: [String] {
        lock.withLock { _warnings }
    }

    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {
        if level == .warning || level == .error {
            let text = message()
            lock.withLock { _warnings.append(text) }
        }
    }
}

@MainActor
@Suite struct AppCoordinatorTests {
    private func makeCoordinator(logger: RecordingLogger = RecordingLogger()) -> AppCoordinator {
        AppCoordinator(logger: logger)
    }

    private let detailA = AppRoute.loanDetail(LoanID("loan-a"))
    private let detailB = AppRoute.loanDetail(LoanID("loan-b"))

    // MARK: - Unwind API

    @Test func popLastRemovesExactlyThatMany() {
        let coordinator = makeCoordinator()
        coordinator.show(detailA)
        coordinator.show(.applyForLoan)
        coordinator.show(detailB)

        coordinator.popLast(2)

        #expect(coordinator.path == [detailA])
        // Over-popping clamps instead of crashing.
        coordinator.popLast(5)
        #expect(coordinator.path.isEmpty)
    }

    @Test func unwindToExistingRouteTrimsEverythingAboveIt() {
        let coordinator = makeCoordinator()
        coordinator.show(detailA)
        coordinator.show(.applyForLoan)
        coordinator.show(detailB)

        coordinator.unwind(to: detailA)

        #expect(coordinator.path == [detailA])
    }

    @Test func unwindToMissingRouteFallsBackToRootAndWarns() {
        let logger = RecordingLogger()
        let coordinator = makeCoordinator(logger: logger)
        coordinator.show(detailA)
        coordinator.show(.applyForLoan)

        coordinator.unwind(to: detailB)

        #expect(coordinator.path.isEmpty)
        #expect(logger.warnings.contains { $0.contains("unwind target missing") })
    }

    @Test func dismissAllAndUnwindDropsModalsThenTrimsThePath() {
        let coordinator = makeCoordinator()
        coordinator.show(detailA)
        coordinator.show(.applyForLoan)
        coordinator.presentPayment(for: LoanID("loan-a"))

        coordinator.dismissAllAndUnwind(to: detailA)

        #expect(coordinator.presentedPaymentLoanID == nil)
        #expect(coordinator.path == [detailA])
    }

    @Test func consumedPaymentConfirmationIsNotBackReachable() {
        // The success unwind: sheet down, path cleared. There is nothing
        // left that could navigate "back" to a confirmation — the screen's
        // state is gone, not merely hidden.
        let coordinator = makeCoordinator()
        coordinator.show(detailA)
        coordinator.presentPayment(for: LoanID("loan-a"))

        coordinator.dismissPayment()
        coordinator.popToRoot()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.presentedPaymentLoanID == nil)
    }

    // MARK: - Pending intent

    @Test func pendingIntentIsConsumedExactlyOnce() {
        let coordinator = makeCoordinator()
        let intent = NavigationIntent(base: .loanList, routes: [detailA], paymentForLoanID: LoanID("loan-a"))
        coordinator.deferUntilAuthenticated(intent)

        #expect(coordinator.consumePendingIntent() == intent)
        // Replay is structurally impossible, not merely avoided.
        #expect(coordinator.consumePendingIntent() == nil)
    }

    @Test func newPendingIntentReplacesTheOld() {
        let coordinator = makeCoordinator()
        coordinator.deferUntilAuthenticated(NavigationIntent(routes: [detailA]))
        coordinator.deferUntilAuthenticated(NavigationIntent(routes: [detailB]))

        #expect(coordinator.consumePendingIntent() == NavigationIntent(routes: [detailB]))
    }

    @Test func applyRebuildsPathAndPresentation() {
        let coordinator = makeCoordinator()
        coordinator.show(.applyForLoan)

        coordinator.apply(NavigationIntent(
            base: .loanList,
            routes: [detailA],
            paymentForLoanID: LoanID("loan-a")
        ))

        #expect(coordinator.path == [detailA])
        #expect(coordinator.presentedPaymentLoanID == LoanID("loan-a"))
    }
}
