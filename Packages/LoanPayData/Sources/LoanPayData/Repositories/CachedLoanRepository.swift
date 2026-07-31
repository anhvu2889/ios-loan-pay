import Foundation
import LoanPayDomain

/// Stale-while-revalidate decorator over ANY `LoanRepository`.
///
/// ARCH: a decorator, not a fork. It conforms to `LoanRepository` (pass-
/// through for search, quotes, later pages) and adds the snapshot streams
/// on top — so it wraps the mock today and the URLSession implementation
/// tomorrow without either knowing caching exists.
public struct CachedLoanRepository: LoanRepository, SnapshotLoanReading {
    enum CacheKey {
        static let firstPage = "loans-page-1"

        static func detail(_ id: LoanID) -> String {
            "loan-detail-\(id.rawValue)"
        }
    }

    private let base: any LoanRepository
    private let cache: CacheStore
    private let sleeper: any Sleeper

    public init(base: any LoanRepository, cache: CacheStore, sleeper: any Sleeper) {
        self.base = base
        self.cache = cache
        self.sleeper = sleeper
    }

    // MARK: - SnapshotLoanReading

    public func loanPageSnapshots(page: Int) -> AsyncThrowingStream<Snapshot<LoanPage>, any Error> {
        snapshotStream(
            cacheKey: page == 1 ? CacheKey.firstPage : nil,
            fetch: { [base, sleeper] in
                // WHY the retry lives HERE now: with SWR, "the initial list
                // load" IS this stream's network leg. Keeping the bounded
                // backoff inside it preserves the front-door-only retry
                // rule with one owner.
                if page == 1 {
                    return try await RetryPolicy.initialListLoad.execute(sleeper: sleeper) {
                        try await base.fetchLoans(page: page)
                    }
                }
                return try await base.fetchLoans(page: page)
            }
        )
    }

    public func loanDetailSnapshots(id: LoanID) -> AsyncThrowingStream<Snapshot<LoanDetail>, any Error> {
        snapshotStream(
            cacheKey: CacheKey.detail(id),
            fetch: { [base] in try await base.fetchLoanDetail(id: id) }
        )
    }

    /// The SWR engine: cached first (instantly), network second, failure
    /// thrown after whatever was yielded.
    private func snapshotStream<Value: Codable & Sendable>(
        cacheKey: String?,
        fetch: @escaping @Sendable () async throws -> Value
    ) -> AsyncThrowingStream<Snapshot<Value>, any Error> {
        let cache = cache
        return AsyncThrowingStream { continuation in
            let task = Task {
                if let cacheKey, let hit = await cache.load(Value.self, forKey: cacheKey) {
                    continuation.yield(Snapshot(value: hit.value, fetchedAt: hit.fetchedAt, isFromCache: true))
                }
                do {
                    let fresh = try await fetch()
                    if let cacheKey {
                        await cache.store(fresh, forKey: cacheKey)
                    }
                    continuation.yield(Snapshot(value: fresh, fetchedAt: Date(), isFromCache: false))
                    continuation.finish()
                } catch {
                    // The consumer decides what a refresh failure means
                    // based on whether it already holds a cached snapshot.
                    continuation.finish(throwing: error)
                }
            }
            // WHY: abandoning the stream (screen dismissed mid-iteration)
            // must cancel the underlying network fetch, or dead screens
            // keep radios busy.
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Payment success invalidates loan data: balances changed server-side;
    /// serving yesterday's numbers after the user just paid would look like
    /// a lost payment.
    public func invalidateLoanData() async {
        await cache.removeAll()
    }

    // MARK: - LoanRepository passthrough

    public func fetchLoans(page: Int) async throws -> LoanPage {
        try await base.fetchLoans(page: page)
    }

    public func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        try await base.fetchLoanDetail(id: id)
    }

    public func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        try await base.fetchPayoffQuote(id: id)
    }

    public func searchLoans(matching query: String) async throws -> [Loan] {
        try await base.searchLoans(matching: query)
    }
}
