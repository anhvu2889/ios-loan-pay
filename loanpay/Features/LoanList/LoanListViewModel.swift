import Foundation
import Observation
import LoanPayDomain

// LANG: `final` is deliberate on every ViewModel — @Observable's generated
// accessors plus subclass overrides is a debugging trap, and nothing here
// is designed for inheritance. `@MainActor` because this type IS the UI
// state; every mutation lands on the main actor by construction, so views
// can never observe a torn update.
@Observable
@MainActor
final class LoanListViewModel {
    /// The screen's primary state. One enum, one source of truth: the view
    /// switches over this and cannot render contradictions (a spinner over
    /// an error, say).
    enum ListState: Equatable {
        case loading
        case loaded
        case empty
        case failed(DomainError)
    }

    /// What the list's tail is doing.
    enum PaginationFooter: Equatable {
        case hidden
        case loadingMore
        case endOfList
    }

    enum SummaryState: Equatable {
        case idle
        case loading
        case loaded(PortfolioSummary)
        case failed
    }

    /// Where the visible list content came from.
    enum Freshness: Equatable {
        case fresh
        case cached(fetchedAt: Date)
        /// Cache on screen, refresh failed — stale and honest about it.
        case staleAfterFailedRefresh(fetchedAt: Date)
    }

    // LANG: `private(set)` everywhere: views READ state, they never assign
    // it. The only way in is a method call, which keeps every transition in
    // this file and every test meaningful.
    private(set) var state: ListState = .loading
    private(set) var sections: [LoanSection] = []
    private(set) var paginationFooter: PaginationFooter = .hidden
    private(set) var summary: SummaryState = .idle
    private(set) var freshness: Freshness = .fresh
    private(set) var isOffline = false
    private(set) var searchResults: [Loan]?
    var searchText: String = "" {
        didSet { searchTextChanged() }
    }

    var isSearchEnabled: Bool {
        flags.isEnabled(.search)
    }

    /// Device models from loaded loans that extend the current query —
    /// "recent models" as suggestion source, no server round-trip.
    var searchSuggestions: [String] {
        guard !searchText.isEmpty else { return [] }
        let models = loadedLoans.map(\.deviceModel)
        return Array(
            Set(models.filter {
                $0.localizedCaseInsensitiveContains(searchText) &&
                $0.caseInsensitiveCompare(searchText) != .orderedSame
            })
        )
        .sorted()
        .prefix(6)
        .map { $0 }
    }

    private var loadedLoans: [Loan] = [] {
        didSet { sections = LoanSection.grouping(loadedLoans) }
    }
    private var hasMorePages = false
    private var highestLoadedPage = 0
    /// Pages currently being fetched — THE dedupe guard. `.onAppear` on a
    /// list row can fire many times per page (cell reuse, fast scrolls);
    /// membership here makes "a page loads exactly once" a set-insert
    /// invariant rather than a timing hope.
    private var pagesInFlight: Set<Int> = []

    // WHY owned task handles: this ViewModel starts background work
    // (summary, search, page loads) whose lifetime IT controls. Owning the
    // handles is what makes "new search cancels the old one" and "dismissal
    // stops the world" one-liners instead of flag soup.
    //
    // LANG: `private(set)` — not `private` — so tests can `await` a handle
    // and observe completion without polling; @ObservationIgnored because a
    // task handle changing is bookkeeping, not something views re-render on.
    @ObservationIgnored private(set) var summaryTask: Task<Void, Never>?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private(set) var callbackTask: Task<Void, Never>?
    @ObservationIgnored private(set) var connectivityTask: Task<Void, Never>?

    private let snapshots: any SnapshotLoanReading
    private let loadLoans: LoadLoansUseCase
    private let loadSummary: LoadPortfolioSummaryUseCase
    private let searchRepository: any LoanRepository
    private let connectivity: any ConnectivityMonitoring
    private let outbox: any OutboxEnqueuing
    private let flags: any FeatureFlags
    private let logger: any AppLogger
    private let sleeper: any Sleeper

    init(
        snapshots: any SnapshotLoanReading,
        loadLoans: LoadLoansUseCase,
        loadSummary: LoadPortfolioSummaryUseCase,
        searchRepository: any LoanRepository,
        connectivity: any ConnectivityMonitoring,
        outbox: any OutboxEnqueuing,
        flags: any FeatureFlags,
        logger: any AppLogger,
        sleeper: any Sleeper
    ) {
        self.snapshots = snapshots
        self.loadLoans = loadLoans
        self.loadSummary = loadSummary
        self.searchRepository = searchRepository
        self.connectivity = connectivity
        self.outbox = outbox
        self.flags = flags
        self.logger = logger
        self.sleeper = sleeper
    }

    // MARK: - Loading

    func loadInitial() async {
        state = .loading
        startConnectivityWatch()
        await loadFirstPage()
    }

    /// Pull-to-refresh. Resets pagination to page 1 — a refreshed list that
    /// still remembers it was "on page 3" would show page-3 data the server
    /// may have reshuffled.
    func refresh() async {
        await loadFirstPage()
    }

    func retry() async {
        state = .loading
        await loadFirstPage()
    }

    /// Stale-while-revalidate: the stream may deliver a cached page first
    /// (rendered instantly, labeled) and the fresh page after. A refresh
    /// failure only becomes a full-screen error when there was NOTHING to
    /// show — cached content downgrades it to a stale label.
    private func loadFirstPage() async {
        loadMoreTask?.cancel()
        do {
            for try await snapshot in snapshots.loanPageSnapshots(page: 1) {
                apply(firstPage: snapshot)
            }
        } catch is CancellationError {
            // The screen went away mid-load; whatever state was on screen
            // stays — rendering an error nobody asked for is worse.
        } catch let error as DomainError {
            handleFirstPageFailure(error)
        } catch {
            handleFirstPageFailure(.unknown)
        }
    }

    private func apply(firstPage snapshot: Snapshot<LoanPage>) {
        pagesInFlight = []
        highestLoadedPage = 1
        hasMorePages = snapshot.value.hasMore
        loadedLoans = snapshot.value.loans
        state = snapshot.value.loans.isEmpty ? .empty : .loaded
        paginationFooter = snapshot.value.hasMore ? .hidden : (snapshot.value.loans.isEmpty ? .hidden : .endOfList)
        freshness = snapshot.isFromCache ? .cached(fetchedAt: snapshot.fetchedAt) : .fresh
        recomputeSummary()
    }

    private func handleFirstPageFailure(_ error: DomainError) {
        if case .cached(let fetchedAt) = freshness, state == .loaded {
            // Offline-with-cache: the list stays, honestly labeled.
            freshness = .staleAfterFailedRefresh(fetchedAt: fetchedAt)
        } else {
            state = .failed(error)
        }
    }

    private func startConnectivityWatch() {
        guard connectivityTask == nil else { return }
        connectivityTask = Task { [weak self, connectivity] in
            for await status in connectivity.statusUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.isOffline = status == .offline
            }
        }
    }

    // MARK: - Pagination

    /// Called from each row's `.onAppear`; only the last loaded row arms
    /// the next page.
    func rowAppeared(_ loan: Loan) {
        guard loan.id == loadedLoans.last?.id, hasMorePages else { return }
        startLoadingPage(highestLoadedPage + 1)
    }

    private func startLoadingPage(_ pageIndex: Int) {
        // The dedupe guard: `insert` is atomic on the main actor, so two
        // onAppear storms for the same trailing row collapse to one fetch.
        guard pagesInFlight.insert(pageIndex).inserted else { return }
        paginationFooter = .loadingMore

        loadMoreTask = Task { [weak self] in
            await self?.loadPage(pageIndex)
        }
    }

    private func loadPage(_ pageIndex: Int) async {
        defer { pagesInFlight.remove(pageIndex) }
        do {
            let page = try await loadLoans.page(pageIndex)
            guard !Task.isCancelled else { return }
            highestLoadedPage = max(highestLoadedPage, pageIndex)
            hasMorePages = page.hasMore
            // Belt-and-suspenders dedupe: even if the backend overlaps
            // pages, a loan renders once (List crashes on duplicate ids).
            let known = Set(loadedLoans.map(\.id))
            loadedLoans += page.loans.filter { !known.contains($0.id) }
            paginationFooter = page.hasMore ? .hidden : .endOfList
            recomputeSummary()
        } catch is CancellationError {
        } catch {
            // WHY no error STATE for pagination: the list on screen is
            // still valid; failing a page quietly returns the footer to
            // idle and the next scroll retries. Only the initial load owns
            // the full-screen error.
            paginationFooter = .hidden
            logger.log(.warning, category: .ui, "pagination fetch failed for a page; will retry on next scroll")
        }
    }

    // MARK: - Portfolio summary

    private func recomputeSummary() {
        summaryTask?.cancel()
        let loans = loadedLoans
        guard !loans.isEmpty else {
            summary = .idle
            return
        }
        summary = .loading
        summaryTask = Task { [weak self, loadSummary] in
            do {
                let result = try await loadSummary.summary(for: loans, currencyCode: "USD")
                guard !Task.isCancelled else { return }
                self?.summary = .loaded(result)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self?.summary = .failed
            }
        }
    }

    // MARK: - Search

    private func searchTextChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        // WHY debounce by task cancellation: each keystroke replaces the
        // whole task. The 300ms sleep is the debounce window — if another
        // character arrives, cancel() lands in the sleep and the stale
        // query never reaches the repository. No timers, no Combine.
        searchTask = Task { [weak self, searchRepository, sleeper] in
            do {
                try await sleeper.sleep(for: .milliseconds(300))
                // WHY the explicit check: Task.sleep throws when cancelled,
                // but a custom sleeper (or a cancellation racing the wake-
                // up) may return normally. Without this line a cancelled
                // task could still fire its stale query at the repository.
                try Task.checkCancellation()
                let results = try await searchRepository.searchLoans(matching: query)
                guard !Task.isCancelled else { return }
                self?.searchResults = results
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                // A failed search shows "no results" rather than an error
                // screen — the loaded list is still right behind it.
                self?.searchResults = []
            }
        }
    }

    // MARK: - Row actions

    func requestCallback(for loan: Loan) {
        callbackTask = Task { [outbox, logger] in
            do {
                try await outbox.enqueue(.supportCallback(topic: "loan", loanID: loan.id))
            } catch {
                logger.log(.error, category: .outbox, "callback enqueue failed")
            }
        }
    }

    /// Owned-task teardown for screen disappearance.
    func cancelOngoingWork() {
        summaryTask?.cancel()
        searchTask?.cancel()
        loadMoreTask?.cancel()
        connectivityTask?.cancel()
        connectivityTask = nil
    }
}
