import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

@MainActor
@Suite struct LoanListViewModelTests {
    private func makeViewModel(
        repository: ProgrammableLoanRepository,
        outbox: OutboxSpy = OutboxSpy(),
        flags: StubFlags = StubFlags(),
        sleeper: any Sleeper = InstantSleeper()
    ) -> LoanListViewModel {
        LoanListViewModel(
            loadLoans: LoadLoansUseCase(repository: repository, sleeper: sleeper),
            loadSummary: LoadPortfolioSummaryUseCase(repository: repository),
            searchRepository: repository,
            outbox: outbox,
            flags: flags,
            logger: SilentLogger(),
            sleeper: sleeper
        )
    }

    private func page(
        _ index: Int,
        ids: [(String, LoanStatus)],
        hasMore: Bool
    ) -> LoanPage {
        LoanPage(
            index: index,
            loans: ids.map { Loan.fixture(id: $0.0, status: $0.1) },
            hasMore: hasMore
        )
    }

    // MARK: - Initial load

    @Test func successGroupsIntoSectionsWithOverdueFirst() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active), ("b", .overdue), ("c", .paidOff), ("d", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.sections.map(\.status) == [.overdue, .active, .paidOff])
        #expect(viewModel.sections.first?.loans.map(\.id) == [LoanID("b")])
        #expect(viewModel.paginationFooter == .endOfList)
    }

    @Test func emptyFirstPageShowsEmptyState() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(LoanPage(index: 1, loans: [], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()

        #expect(viewModel.state == .empty)
    }

    @Test func persistentOfflineFailureLandsInFailedStateAfterAutoRetry() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .failure(.offline),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()

        #expect(viewModel.state == .failed(.offline))
        // 1 attempt + 2 auto-retries: the initial load policy, visible here.
        await #expect(repository.pageRequests == [1, 1, 1])
    }

    @Test func nonRetryableFailureFailsImmediately() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .failure(.notFound),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()

        #expect(viewModel.state == .failed(.notFound))
        await #expect(repository.pageRequests == [1])
    }

    // MARK: - Pagination

    @Test func lastRowAppearingLoadsTheNextPageExactlyOnce() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
            2: .success(page(2, ids: [("c", .active)], hasMore: false)),
        ])
        let gate = Gate()
        await repository.setGate(gate, forPage: 2)
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadInitial()
        let lastLoan = Loan.fixture(id: "b")

        // A fast scroll fires onAppear for the trailing row repeatedly;
        // with page 2 gated, every duplicate arrives while the first fetch
        // is provably still in flight.
        viewModel.rowAppeared(lastLoan)
        viewModel.rowAppeared(lastLoan)
        viewModel.rowAppeared(lastLoan)
        #expect(viewModel.paginationFooter == .loadingMore)

        await gate.open()
        await viewModel.loadMoreTask?.value

        await #expect(repository.pageRequests == [1, 2])
        #expect(viewModel.sections.flatMap(\.loans).count == 3)
        #expect(viewModel.paginationFooter == .endOfList)
    }

    @Test func refreshResetsToPageOneAndReArmsPagination() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
            2: .success(page(2, ids: [("c", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()
        viewModel.rowAppeared(Loan.fixture(id: "b"))
        await viewModel.loadMoreTask?.value
        #expect(viewModel.sections.flatMap(\.loans).count == 3)

        await viewModel.refresh()
        // Back to page 1 content only…
        #expect(viewModel.sections.flatMap(\.loans).count == 2)

        // …and page 2 is loadable AGAIN — the dedupe guard was reset.
        viewModel.rowAppeared(Loan.fixture(id: "b"))
        await viewModel.loadMoreTask?.value
        await #expect(repository.pageRequests == [1, 2, 1, 2])
        #expect(viewModel.sections.flatMap(\.loans).count == 3)
    }

    @Test func endOfListDisarmsFurtherLoads() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadInitial()

        viewModel.rowAppeared(Loan.fixture(id: "a"))
        await viewModel.loadMoreTask?.value

        await #expect(repository.pageRequests == [1])
        #expect(viewModel.paginationFooter == .endOfList)
    }

    @Test func nonTrailingRowNeverTriggersPagination() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
        ])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadInitial()

        viewModel.rowAppeared(Loan.fixture(id: "a"))

        #expect(viewModel.loadMoreTask == nil)
        await #expect(repository.pageRequests == [1])
    }

    // MARK: - Portfolio summary

    @Test func summaryAggregatesLoadedLoans() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(LoanPage(index: 1, loans: [
                Loan.fixture(id: "a", status: .active, outstanding: "40.00"),
                Loan.fixture(id: "b", status: .overdue, outstanding: "60.00"),
            ], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadInitial()
        await viewModel.summaryTask?.value

        guard case .loaded(let summary) = viewModel.summary else {
            Issue.record("expected loaded summary, got \(viewModel.summary)")
            return
        }
        #expect(summary.totalOutstanding == .usd("100.00"))
        #expect(summary.overdueLoanCount == 1)
    }

    // MARK: - Search

    @Test func searchDebouncesToASingleRequestForTheLatestText() async {
        let repository = ProgrammableLoanRepository(
            pages: [1: .success(page(1, ids: [("a", .active)], hasMore: false))],
            searchResult: [Loan.fixture(id: "s1", deviceModel: "Galaxy A15")]
        )
        let debounceGate = Gate()
        let viewModel = makeViewModel(repository: repository, sleeper: GateSleeper(gate: debounceGate))
        await viewModel.loadInitial()

        // Two keystrokes inside the debounce window: the first task dies in
        // its sleep; only the second survives to touch the repository.
        viewModel.searchText = "ga"
        viewModel.searchText = "gal"

        await debounceGate.open()
        await viewModel.searchTask?.value

        await #expect(repository.searchQueries == ["gal"])
        #expect(viewModel.searchResults?.map(\.id) == [LoanID("s1")])
    }

    @Test func clearingSearchTextRestoresTheListWithoutARequest() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadInitial()

        viewModel.searchText = ""

        #expect(viewModel.searchResults == nil)
        await #expect(repository.searchQueries.isEmpty)
    }

    @Test func suggestionsComeFromLoadedDeviceModels() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(LoanPage(index: 1, loans: [
                Loan.fixture(id: "a", deviceModel: "Galaxy A15"),
                Loan.fixture(id: "b", deviceModel: "Galaxy A25"),
                Loan.fixture(id: "c", deviceModel: "Redmi 13C"),
            ], hasMore: false)),
        ])
        let gate = Gate() // keep the search itself parked; suggestions are synchronous
        let viewModel = makeViewModel(repository: repository, sleeper: GateSleeper(gate: gate))
        await viewModel.loadInitial()

        viewModel.searchText = "galaxy"

        #expect(viewModel.searchSuggestions == ["Galaxy A15", "Galaxy A25"])
    }

    @Test func searchFlagOffHidesSearch() async {
        let repository = ProgrammableLoanRepository(pages: [:])
        let viewModel = makeViewModel(repository: repository, flags: StubFlags(disabled: [.search]))
        #expect(!viewModel.isSearchEnabled)
    }

    // MARK: - Row actions

    @Test func requestCallbackEnqueuesASupportPayload() async {
        let repository = ProgrammableLoanRepository(pages: [
            1: .success(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let outbox = OutboxSpy()
        let viewModel = makeViewModel(repository: repository, outbox: outbox)
        await viewModel.loadInitial()

        viewModel.requestCallback(for: Loan.fixture(id: "a"))
        await viewModel.callbackTask?.value

        await #expect(outbox.enqueued == [.supportCallback(topic: "loan", loanID: LoanID("a"))])
    }
}
