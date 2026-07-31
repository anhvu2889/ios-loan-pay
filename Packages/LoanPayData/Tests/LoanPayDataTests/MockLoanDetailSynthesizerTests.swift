import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct MockLoanDetailSynthesizerTests {
    @Test func synthesizedBookIsConsistentWithSummaryNumbers() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        // loan-001: principal 240, monthly 20, outstanding 140 → 12
        // installments, 5 paid, 6th due.
        let detail = try await repository.fetchLoanDetail(id: LoanID("loan-001"))

        #expect(detail.installments.count == 12)
        #expect(detail.installments.count(where: { $0.status == .paid }) == 5)
        #expect(detail.installments[5].status == .due)
        #expect(detail.installments.suffix(6).allSatisfy { $0.status == .upcoming })

        // The unpaid installments must sum exactly to the outstanding
        // balance — mock data that disagrees with itself teaches bugs.
        let unpaidTotal = try Money.sum(
            detail.installments.filter { $0.status != .paid }.map(\.amount),
            currencyCode: "USD"
        )
        #expect(unpaidTotal == detail.loan.outstandingBalance)
    }

    @Test func overdueLoanMarksTheNextUnpaidInstallmentOverdue() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        // loan-002: overdue, 2 paid.
        let detail = try await repository.fetchLoanDetail(id: LoanID("loan-002"))
        #expect(detail.installments[2].status == .overdue)
    }

    @Test func balanceHistoryDescendsFromPrincipalToOutstanding() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        let detail = try await repository.fetchLoanDetail(id: LoanID("loan-001"))

        #expect(detail.balanceHistory.first?.balance == detail.loan.principal)
        #expect(detail.balanceHistory.last?.balance == detail.loan.outstandingBalance)
        let balances = detail.balanceHistory.map(\.balance.amount)
        #expect(balances == balances.sorted(by: >))
    }

    @Test func paidOffLoanIsFullyPaidWithNoDueInstallment() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        // loan-003: paidOff.
        let detail = try await repository.fetchLoanDetail(id: LoanID("loan-003"))
        #expect(detail.installments.allSatisfy { $0.status == .paid })
    }
}
