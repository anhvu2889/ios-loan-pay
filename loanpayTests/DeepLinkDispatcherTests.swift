import Foundation
import Testing
import LoanPayDomain
import LoanPayFeatureKit
import PaymentFeature
@testable import loanpay

@MainActor
@Suite struct DeepLinkDispatcherTests {
    private func makeDispatcher(logger: RecordingLogger = RecordingLogger()) -> DeepLinkDispatcher {
        let dispatcher = DeepLinkDispatcher(logger: logger)
        FeatureRegistration.registerAll(dispatcher: dispatcher)
        return dispatcher
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    // MARK: - Prefix routing

    @Test func loansLinkRoutesToTheLoansHandler() {
        let outcome = makeDispatcher().dispatch(url("loanpay://loans/loan-001"), isAuthenticated: true)
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(LoanID("loan-001"))]
        )))
    }

    @Test func bareLoansLinkOpensTheList() {
        let outcome = makeDispatcher().dispatch(url("loanpay://loans"), isAuthenticated: true)
        #expect(outcome == .handled(NavigationIntent(base: .loanList)))
    }

    // MARK: - Multi-segment parse

    @Test func paymentLinkParsesLoanAndMethodsSegments() {
        let outcome = makeDispatcher().dispatch(
            url("loanpay://payment/loan-004/methods"),
            isAuthenticated: true
        )
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(LoanID("loan-004"))],
            paymentForLoanID: LoanID("loan-004")
        )))
    }

    @Test func paymentLinkWithoutMethodsSegmentAlsoParses() {
        let outcome = makeDispatcher().dispatch(url("loanpay://payment/loan-004"), isAuthenticated: true)
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(LoanID("loan-004"))],
            paymentForLoanID: LoanID("loan-004")
        )))
    }

    // MARK: - Auth gating

    @Test func guardedLinkWhileLoggedOutRequiresAuthWithTheFullIntent() {
        let outcome = makeDispatcher().dispatch(
            url("loanpay://payment/loan-004/methods"),
            isAuthenticated: false
        )
        #expect(outcome == .requiresAuth(NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(LoanID("loan-004"))],
            paymentForLoanID: LoanID("loan-004")
        )))
    }

    @Test func requiresAuthIntentFlowsThroughThePendingSlotOnce() {
        let dispatcher = makeDispatcher()
        let coordinator = AppCoordinator(logger: RecordingLogger())

        guard case .requiresAuth(let intent)? = dispatcher.dispatch(
            url("loanpay://loans/loan-007"),
            isAuthenticated: false
        ) else {
            Issue.record("expected requiresAuth")
            return
        }
        coordinator.deferUntilAuthenticated(intent)

        // Auth completes → the stored intent applies exactly once.
        if let pending = coordinator.consumePendingIntent() {
            coordinator.apply(pending)
        }
        #expect(coordinator.path == [.loanDetail(LoanID("loan-007"))])
        #expect(coordinator.consumePendingIntent() == nil)
    }

    // MARK: - Dropped links

    @Test func unknownFeaturePrefixIsDroppedAndLogged() {
        let logger = RecordingLogger()
        let outcome = makeDispatcher(logger: logger).dispatch(
            url("loanpay://wallet/topup"),
            isAuthenticated: true
        )
        #expect(outcome == nil)
        #expect(logger.warnings.contains { $0.contains("no handler registered") })
    }

    @Test func wrongSchemeIsDropped() {
        let outcome = makeDispatcher().dispatch(url("https://loans/loan-001"), isAuthenticated: true)
        #expect(outcome == nil)
    }

    @Test func unrecognizedPathShapeIsDropped() {
        let logger = RecordingLogger()
        let dispatcher = makeDispatcher(logger: logger)
        #expect(dispatcher.dispatch(url("loanpay://loans/a/b/c"), isAuthenticated: true) == nil)
        #expect(dispatcher.dispatch(url("loanpay://payment/loan-1/refund"), isAuthenticated: true) == nil)
        #expect(logger.warnings.contains { $0.contains("did not recognize") })
    }

    @Test func malformedIdentifiersAreRejectedByValidation() {
        let dispatcher = makeDispatcher()
        // Traversal-shaped and illegal-character ids die in
        // DeepLinkParameter, not in a repository call.
        #expect(dispatcher.dispatch(url("loanpay://loans/..%2F..%2Fetc"), isAuthenticated: true) == nil)
        #expect(dispatcher.dispatch(url("loanpay://loans/loan_001%3Bdrop"), isAuthenticated: true) == nil)
    }
}
