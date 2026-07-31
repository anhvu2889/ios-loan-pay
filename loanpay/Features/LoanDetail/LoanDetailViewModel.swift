import Foundation
import Observation
import LoanPayDomain

@Observable
@MainActor
final class LoanDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(LoanDetail)
        case failed(DomainError)
    }

    enum Freshness: Equatable {
        case fresh
        case cached(fetchedAt: Date)
        case staleAfterFailedRefresh(fetchedAt: Date)
    }

    private(set) var state: State = .loading
    private(set) var freshness: Freshness = .fresh

    let loanID: LoanID
    private let snapshots: any SnapshotLoanReading

    init(loanID: LoanID, snapshots: any SnapshotLoanReading) {
        self.loanID = loanID
        self.snapshots = snapshots
    }

    // Stale-while-revalidate: a cached detail renders in one frame (this is
    // what makes offline deep links land on content instead of a blank
    // screen), then the refresh replaces it or downgrades it to "stale".
    //
    // WHY no auto-retry: the bounded-backoff policy is reserved for the
    // app's front door. Here a cached copy usually papers over the blip,
    // and a visible manual Try Again beats hidden waiting.
    func load() async {
        do {
            for try await snapshot in snapshots.loanDetailSnapshots(id: loanID) {
                state = .loaded(snapshot.value)
                freshness = snapshot.isFromCache ? .cached(fetchedAt: snapshot.fetchedAt) : .fresh
            }
        } catch is CancellationError {
            // Back navigation mid-load: leave the state alone; the screen
            // is already gone.
        } catch let error as DomainError {
            handleRefreshFailure(error)
        } catch {
            handleRefreshFailure(.unknown)
        }
    }

    func retry() async {
        state = .loading
        freshness = .fresh
        await load()
    }

    private func handleRefreshFailure(_ error: DomainError) {
        if case .cached(let fetchedAt) = freshness, case .loaded = state {
            freshness = .staleAfterFailedRefresh(fetchedAt: fetchedAt)
        } else {
            state = .failed(error)
        }
    }
}
