import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

@MainActor
@Suite struct LoanDetailViewModelTests {
    @Test func loadSuccessExposesTheDetail() async {
        let detail = LoanDetail.fixture(id: "loan-7")
        let repository = ProgrammableLoanRepository(pages: [:], detailResult: .success(detail))
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-7"), repository: repository)

        await viewModel.load()

        #expect(viewModel.state == .loaded(detail))
        await #expect(repository.detailRequests == [LoanID("loan-7")])
    }

    @Test func notFoundFailsWithoutRetryOffer() async {
        let repository = ProgrammableLoanRepository(pages: [:], detailResult: .failure(.notFound))
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-x"), repository: repository)

        await viewModel.load()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("expected failed state")
            return
        }
        #expect(error == .notFound)
        #expect(!error.isRetryable)
        // Detail loads do NOT auto-retry — one request only.
        await #expect(repository.detailRequests.count == 1)
    }

    @Test func retryAfterTransientFailureRecovers() async {
        let repository = ProgrammableLoanRepository(pages: [:], detailResult: .failure(.timeout))
        let viewModel = LoanDetailViewModel(loanID: LoanID("loan-7"), repository: repository)

        await viewModel.load()
        #expect(viewModel.state == .failed(.timeout))

        let detail = LoanDetail.fixture(id: "loan-7")
        await repository.setDetailResult(.success(detail))
        await viewModel.retry()

        #expect(viewModel.state == .loaded(detail))
        await #expect(repository.detailRequests.count == 2)
    }
}
