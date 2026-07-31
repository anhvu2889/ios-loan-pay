import Foundation
import Testing
import LoanPayDomain
import LoanPayFeatureKit
@testable import loanpay

@MainActor
@Suite struct PendingDestinationTests {
    @Test func consumeReturnsTheStoredRouteExactlyOnce() {
        let coordinator = AppCoordinator()
        coordinator.deferUntilAuthenticated(.loanDetail(LoanID("loan-9")))

        #expect(coordinator.consumePendingDestination() == .loanDetail(LoanID("loan-9")))
        // Second consume returns nothing — replay is structurally
        // impossible, not merely avoided.
        #expect(coordinator.consumePendingDestination() == nil)
    }

    @Test func consumeWithNothingPendingReturnsNil() {
        let coordinator = AppCoordinator()
        #expect(coordinator.consumePendingDestination() == nil)
    }

    @Test func newDestinationReplacesTheOldOne() {
        let coordinator = AppCoordinator()
        coordinator.deferUntilAuthenticated(.loanDetail(LoanID("first")))
        coordinator.deferUntilAuthenticated(.applyForLoan)

        #expect(coordinator.consumePendingDestination() == .applyForLoan)
        #expect(coordinator.consumePendingDestination() == nil)
    }
}
