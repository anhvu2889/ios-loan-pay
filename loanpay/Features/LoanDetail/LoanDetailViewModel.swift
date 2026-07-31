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

    private(set) var state: State = .loading

    let loanID: LoanID
    private let repository: any LoanRepository

    init(loanID: LoanID, repository: any LoanRepository) {
        self.loanID = loanID
        self.repository = repository
    }

    // WHY no auto-retry here: the bounded-backoff policy is reserved for
    // the app's front door (initial list load), where the radio is often
    // still waking. Detail sits behind a visible list — a failure here gets
    // an honest error with a manual Try Again, which beats a screen that
    // sits silent for 1.5s of hidden retries.
    func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.fetchLoanDetail(id: loanID))
        } catch is CancellationError {
            // Back navigation mid-load: leave the state alone; the screen
            // is already gone.
        } catch let error as DomainError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    func retry() async {
        await load()
    }
}
