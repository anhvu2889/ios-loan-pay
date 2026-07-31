import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

@MainActor
@Suite struct LoanListViewModelTests {
    private func makeViewModel(
        provider: FakeSnapshotProvider,
        repository: ProgrammableLoanRepository = ProgrammableLoanRepository(pages: [:]),
        connectivity: FakeConnectivity = FakeConnectivity(),
        outbox: OutboxSpy = OutboxSpy(),
        flags: StubFlags = StubFlags(),
        sleeper: any Sleeper = InstantSleeper()
    ) -> LoanListViewModel {
        LoanListViewModel(
            snapshots: provider,
            loadLoans: LoadLoansUseCase(repository: repository, sleeper: sleeper),
            loadSummary: LoadPortfolioSummaryUseCase(repository: repository),
            searchRepository: repository,
            connectivity: connectivity,
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
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active), ("b", .overdue), ("c", .paidOff), ("d", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.sections.map(\.status) == [.overdue, .active, .paidOff])
        #expect(viewModel.sections.first?.loans.map(\.id) == [LoanID("b")])
        #expect(viewModel.paginationFooter == .endOfList)
        #expect(viewModel.freshness == .fresh)
    }

    @Test func emptyFirstPageShowsEmptyState() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(LoanPage(index: 1, loans: [], hasMore: false)),
        ])
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        #expect(viewModel.state == .empty)
    }

    @Test func failureWithNoCacheLandsInFailedState() async {
        let provider = FakeSnapshotProvider(pageError: .offline)
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        #expect(viewModel.state == .failed(.offline))
    }

    @Test func nonRetryableFailureExposesItsError() async {
        let provider = FakeSnapshotProvider(pageError: .notFound)
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        #expect(viewModel.state == .failed(.notFound))
    }

    // MARK: - Stale-while-revalidate

    @Test func cachedThenFreshEndsWithFreshContent() async {
        let stale = page(1, ids: [("old", .active)], hasMore: false)
        let current = page(1, ids: [("new", .active)], hasMore: false)
        let provider = FakeSnapshotProvider(pageSnapshots: [
            cached(stale, at: testDate),
            fresh(current),
        ])
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        #expect(viewModel.sections.flatMap(\.loans).map(\.id) == [LoanID("new")])
        #expect(viewModel.freshness == .fresh)
    }

    @Test func cachedWithFailedRefreshKeepsContentAndTurnsStale() async {
        let stale = page(1, ids: [("old", .active)], hasMore: false)
        let provider = FakeSnapshotProvider(
            pageSnapshots: [cached(stale, at: testDate)],
            pageError: .offline
        )
        let viewModel = makeViewModel(provider: provider)

        await viewModel.loadInitial()

        // No error screen: cached content + an honest stale label wins.
        #expect(viewModel.state == .loaded)
        #expect(viewModel.sections.flatMap(\.loans).map(\.id) == [LoanID("old")])
        #expect(viewModel.freshness == .staleAfterFailedRefresh(fetchedAt: testDate))
    }

    // MARK: - Connectivity

    @Test func offlineStatusRaisesTheBanner() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(
            provider: provider,
            connectivity: FakeConnectivity(statuses: [.online, .offline])
        )

        await viewModel.loadInitial()
        await viewModel.connectivityTask?.value

        #expect(viewModel.isOffline)
    }

    // MARK: - Pagination

    @Test func lastRowAppearingLoadsTheNextPageExactlyOnce() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
        ])
        let repository = ProgrammableLoanRepository(pages: [
            2: .success(page(2, ids: [("c", .active)], hasMore: false)),
        ])
        let gate = Gate()
        await repository.setGate(gate, forPage: 2)
        let viewModel = makeViewModel(provider: provider, repository: repository)
        await viewModel.loadInitial()
        let lastLoan = Loan.fixture(id: "b")

        viewModel.rowAppeared(lastLoan)
        viewModel.rowAppeared(lastLoan)
        viewModel.rowAppeared(lastLoan)
        #expect(viewModel.paginationFooter == .loadingMore)

        await gate.open()
        await viewModel.loadMoreTask?.value

        await #expect(repository.pageRequests == [2])
        #expect(viewModel.sections.flatMap(\.loans).count == 3)
        #expect(viewModel.paginationFooter == .endOfList)
    }

    @Test func refreshResetsToPageOneAndReArmsPagination() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
        ])
        let repository = ProgrammableLoanRepository(pages: [
            2: .success(page(2, ids: [("c", .active)], hasMore: false)),
        ])
        let viewModel = makeViewModel(provider: provider, repository: repository)

        await viewModel.loadInitial()
        viewModel.rowAppeared(Loan.fixture(id: "b"))
        await viewModel.loadMoreTask?.value
        #expect(viewModel.sections.flatMap(\.loans).count == 3)

        await viewModel.refresh()
        #expect(viewModel.sections.flatMap(\.loans).count == 2)

        // Page 2 is loadable AGAIN — the dedupe guard was reset.
        viewModel.rowAppeared(Loan.fixture(id: "b"))
        await viewModel.loadMoreTask?.value
        await #expect(repository.pageRequests == [2, 2])
        #expect(viewModel.sections.flatMap(\.loans).count == 3)
    }

    @Test func endOfListDisarmsFurtherLoads() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let repository = ProgrammableLoanRepository(pages: [:])
        let viewModel = makeViewModel(provider: provider, repository: repository)
        await viewModel.loadInitial()

        viewModel.rowAppeared(Loan.fixture(id: "a"))
        await viewModel.loadMoreTask?.value

        await #expect(repository.pageRequests.isEmpty)
        #expect(viewModel.paginationFooter == .endOfList)
    }

    @Test func nonTrailingRowNeverTriggersPagination() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active), ("b", .active)], hasMore: true)),
        ])
        let repository = ProgrammableLoanRepository(pages: [:])
        let viewModel = makeViewModel(provider: provider, repository: repository)
        await viewModel.loadInitial()

        viewModel.rowAppeared(Loan.fixture(id: "a"))

        #expect(viewModel.loadMoreTask == nil)
        await #expect(repository.pageRequests.isEmpty)
    }

    // MARK: - Portfolio summary

    @Test func summaryAggregatesLoadedLoans() async {
        let loans = [
            Loan.fixture(id: "a", status: .active, outstanding: "40.00"),
            Loan.fixture(id: "b", status: .overdue, outstanding: "60.00"),
        ]
        let firstPage = LoanPage(index: 1, loans: loans, hasMore: false)
        let provider = FakeSnapshotProvider(pageSnapshots: [fresh(firstPage)])
        // The repository serves the payoff quotes for the same loans.
        let repository = ProgrammableLoanRepository(pages: [1: .success(firstPage)])
        let viewModel = makeViewModel(provider: provider, repository: repository)

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
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let repository = ProgrammableLoanRepository(
            pages: [:],
            searchResult: [Loan.fixture(id: "s1", deviceModel: "Galaxy A15")]
        )
        let debounceGate = Gate()
        let viewModel = makeViewModel(
            provider: provider,
            repository: repository,
            sleeper: GateSleeper(gate: debounceGate)
        )
        await viewModel.loadInitial()

        viewModel.searchText = "ga"
        viewModel.searchText = "gal"

        await debounceGate.open()
        await viewModel.searchTask?.value

        await #expect(repository.searchQueries == ["gal"])
        #expect(viewModel.searchResults?.map(\.id) == [LoanID("s1")])
    }

    @Test func clearingSearchTextRestoresTheListWithoutARequest() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let repository = ProgrammableLoanRepository(pages: [:])
        let viewModel = makeViewModel(provider: provider, repository: repository)
        await viewModel.loadInitial()

        viewModel.searchText = ""

        #expect(viewModel.searchResults == nil)
        await #expect(repository.searchQueries.isEmpty)
    }

    @Test func suggestionsComeFromLoadedDeviceModels() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(LoanPage(index: 1, loans: [
                Loan.fixture(id: "a", deviceModel: "Galaxy A15"),
                Loan.fixture(id: "b", deviceModel: "Galaxy A25"),
                Loan.fixture(id: "c", deviceModel: "Redmi 13C"),
            ], hasMore: false)),
        ])
        let gate = Gate()
        let viewModel = makeViewModel(provider: provider, sleeper: GateSleeper(gate: gate))
        await viewModel.loadInitial()

        viewModel.searchText = "galaxy"

        #expect(viewModel.searchSuggestions == ["Galaxy A15", "Galaxy A25"])
    }

    @Test func searchFlagOffHidesSearch() async {
        let viewModel = makeViewModel(
            provider: FakeSnapshotProvider(),
            flags: StubFlags(disabled: [.search])
        )
        #expect(!viewModel.isSearchEnabled)
    }

    // MARK: - Row actions

    @Test func requestCallbackEnqueuesASupportPayload() async {
        let provider = FakeSnapshotProvider(pageSnapshots: [
            fresh(page(1, ids: [("a", .active)], hasMore: false)),
        ])
        let outbox = OutboxSpy()
        let viewModel = makeViewModel(provider: provider, outbox: outbox)
        await viewModel.loadInitial()

        viewModel.requestCallback(for: Loan.fixture(id: "a"))
        await viewModel.callbackTask?.value

        await #expect(outbox.enqueued == [.supportCallback(topic: "loan", loanID: LoanID("a"))])
    }
}
