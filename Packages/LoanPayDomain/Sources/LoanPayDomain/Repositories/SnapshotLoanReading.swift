import Foundation

/// Stale-while-revalidate reads for the loan surfaces that render offline.
///
/// The stream contract:
///  1. If a cached value exists it is yielded FIRST, immediately, marked
///     `isFromCache` — the user sees data in one frame, network or not.
///  2. A network refresh follows; success yields a fresh snapshot (and
///     re-primes the cache).
///  3. A refresh failure FINISHES THE STREAM THROWING. Consumers that
///     already received a cached snapshot treat the error as "stale, not
///     broken" (banner, not error screen); consumers with nothing render
///     the failure.
///
/// WHY a stream and not `(cached?, fresh)` tuples: the two arrivals are
/// separated by real network time; a tuple would force waiting for the
/// slow half — the exact thing SWR exists to avoid.
public protocol SnapshotLoanReading: Sendable {
    func loanPageSnapshots(page: Int) -> AsyncThrowingStream<Snapshot<LoanPage>, any Error>
    func loanDetailSnapshots(id: LoanID) -> AsyncThrowingStream<Snapshot<LoanDetail>, any Error>
}
