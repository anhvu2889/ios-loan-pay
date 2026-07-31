import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

@MainActor
@Suite struct LoanDetailViewModelTests {
    @Test func freshLoadExposesTheDetailUnlabeled() async {
        let detail = LoanDetail.fixture(id: "loan-7")
        let provider = FakeSnapshotProvider(detailSnapshots: [fresh(detail)])
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-7"), snapshots: provider)

        await viewModel.load()

        #expect(viewModel.state == .loaded(detail))
        #expect(viewModel.freshness == .fresh)
    }

    @Test func cachedThenFreshEndsFresh() async {
        let stale = LoanDetail.fixture(id: "loan-7", status: .overdue)
        let current = LoanDetail.fixture(id: "loan-7")
        let provider = FakeSnapshotProvider(detailSnapshots: [
            cached(stale, at: testDate),
            fresh(current),
        ])
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-7"), snapshots: provider)

        await viewModel.load()

        #expect(viewModel.state == .loaded(current))
        #expect(viewModel.freshness == .fresh)
    }

    @Test func offlineDeepLinkRendersFromCacheNeverBlank() async {
        // Offline + cache: content with a stale label, not an error screen.
        let stale = LoanDetail.fixture(id: "loan-7")
        let provider = FakeSnapshotProvider(
            detailSnapshots: [cached(stale, at: testDate)],
            detailError: .offline
        )
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-7"), snapshots: provider)

        await viewModel.load()

        #expect(viewModel.state == .loaded(stale))
        #expect(viewModel.freshness == .staleAfterFailedRefresh(fetchedAt: testDate))
    }

    @Test func failureWithNoCacheFailsHonestly() async {
        let provider = FakeSnapshotProvider(detailError: .notFound)
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-x"), snapshots: provider)

        await viewModel.load()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("expected failed state")
            return
        }
        #expect(error == .notFound)
        #expect(!error.isRetryable)
    }
}
