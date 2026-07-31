import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

/// Scriptable base repository for the decorator tests.
actor ScriptableBaseRepository: LoanRepository {
    var pageResult: Result<LoanPage, DomainError>
    private(set) var fetchCount = 0

    init(pageResult: Result<LoanPage, DomainError>) {
        self.pageResult = pageResult
    }

    func setPageResult(_ result: Result<LoanPage, DomainError>) {
        pageResult = result
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        fetchCount += 1
        return try pageResult.get()
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        throw DomainError.unknown
    }

    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        throw DomainError.unknown
    }

    func searchLoans(matching query: String) async throws -> [Loan] {
        throw DomainError.unknown
    }
}

@Suite struct CachedLoanRepositoryTests {
    private let networkPage = LoanPage(
        index: 1,
        loans: [Loan(
            id: LoanID("fresh-1"),
            deviceModel: "Galaxy A15",
            deviceImageURL: nil,
            principal: Money(amount: 240, currencyCode: "USD"),
            outstandingBalance: Money(amount: 140, currencyCode: "USD"),
            monthlyInstallment: Money(amount: 20, currencyCode: "USD"),
            status: .active,
            nextInstallmentDue: nil
        )],
        hasMore: true
    )

    private let cachedPage = LoanPage(index: 1, loans: [], hasMore: false)

    private func makeCache() -> CacheStore {
        CacheStore(directoryName: "CachedRepoTests-\(UUID().uuidString)")
    }

    private func collect(
        _ stream: AsyncThrowingStream<Snapshot<LoanPage>, any Error>
    ) async -> (snapshots: [Snapshot<LoanPage>], error: DomainError?) {
        var snapshots: [Snapshot<LoanPage>] = []
        do {
            for try await snapshot in stream {
                snapshots.append(snapshot)
            }
            return (snapshots, nil)
        } catch let error as DomainError {
            return (snapshots, error)
        } catch {
            return (snapshots, .unknown)
        }
    }

    // MARK: - The 4-way matrix: cache hit/miss × network ok/fail

    @Test func missAndNetworkOKYieldsOneFreshSnapshotAndPrimesTheCache() async {
        let base = ScriptableBaseRepository(pageResult: .success(networkPage))
        let cache = makeCache()
        let repository = CachedLoanRepository(base: base, cache: cache, sleeper: InstantTestSleeper())

        let outcome = await collect(repository.loanPageSnapshots(page: 1))

        #expect(outcome.snapshots.map(\.isFromCache) == [false])
        #expect(outcome.snapshots.first?.value == networkPage)
        #expect(outcome.error == nil)
        // Primed: the next stream starts from cache.
        #expect(await cache.load(LoanPage.self, forKey: "loans-page-1")?.value == networkPage)
    }

    @Test func missAndNetworkFailThrowsWithNoSnapshots() async {
        let base = ScriptableBaseRepository(pageResult: .failure(.notFound))
        let repository = CachedLoanRepository(base: base, cache: makeCache(), sleeper: InstantTestSleeper())

        let outcome = await collect(repository.loanPageSnapshots(page: 1))

        #expect(outcome.snapshots.isEmpty)
        #expect(outcome.error == .notFound)
    }

    @Test func hitAndNetworkOKYieldsCachedThenFresh() async {
        let base = ScriptableBaseRepository(pageResult: .success(networkPage))
        let cache = makeCache()
        await cache.store(cachedPage, forKey: "loans-page-1")
        let repository = CachedLoanRepository(base: base, cache: cache, sleeper: InstantTestSleeper())

        let outcome = await collect(repository.loanPageSnapshots(page: 1))

        // The SWR order: stale instantly, truth when it arrives.
        #expect(outcome.snapshots.map(\.isFromCache) == [true, false])
        #expect(outcome.snapshots.first?.value == cachedPage)
        #expect(outcome.snapshots.last?.value == networkPage)
        #expect(outcome.error == nil)
    }

    @Test func hitAndNetworkFailYieldsCachedThenThrows() async {
        let base = ScriptableBaseRepository(pageResult: .failure(.notFound))
        let cache = makeCache()
        await cache.store(cachedPage, forKey: "loans-page-1")
        let repository = CachedLoanRepository(base: base, cache: cache, sleeper: InstantTestSleeper())

        let outcome = await collect(repository.loanPageSnapshots(page: 1))

        // Offline deep-link case: content renders from cache, the error
        // arrives as "stale", never as a blank screen.
        #expect(outcome.snapshots.map(\.isFromCache) == [true])
        #expect(outcome.error == .notFound)
    }

    // MARK: - Retry stays at the front door

    @Test func firstPageNetworkLegRetriesWithTheBoundedPolicy() async {
        let base = ScriptableBaseRepository(pageResult: .failure(.timeout))
        let repository = CachedLoanRepository(base: base, cache: makeCache(), sleeper: InstantTestSleeper())

        _ = await collect(repository.loanPageSnapshots(page: 1))
        // 1 attempt + 2 retries.
        #expect(await base.fetchCount == 3)

        await base.setPageResult(.failure(.timeout))
        _ = await collect(repository.loanPageSnapshots(page: 2))
        // Later pages: exactly one attempt (3 + 1).
        #expect(await base.fetchCount == 4)
    }

    // MARK: - Invalidation

    @Test func invalidationEmptiesTheCacheSoTheNextReadIsAMiss() async {
        let base = ScriptableBaseRepository(pageResult: .success(networkPage))
        let cache = makeCache()
        await cache.store(cachedPage, forKey: "loans-page-1")
        let repository = CachedLoanRepository(base: base, cache: cache, sleeper: InstantTestSleeper())

        await repository.invalidateLoanData()

        let outcome = await collect(repository.loanPageSnapshots(page: 1))
        // No cached snapshot — the payment changed the numbers; yesterday's
        // balances must not flash first.
        #expect(outcome.snapshots.map(\.isFromCache) == [false])
    }
}

struct InstantTestSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {}
}
