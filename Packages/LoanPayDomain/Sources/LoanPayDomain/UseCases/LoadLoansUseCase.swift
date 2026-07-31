import Foundation

// ARCH: a use case earns its file when it encodes a *rule*, not just a
// pass-through. The rule here: the initial page auto-retries on transient
// failure, later pages never do. Screens call this type and cannot get that
// policy wrong.
public struct LoadLoansUseCase: Sendable {
    private let repository: any LoanRepository
    private let sleeper: any Sleeper

    public init(repository: any LoanRepository, sleeper: any Sleeper) {
        self.repository = repository
        self.sleeper = sleeper
    }

    /// First page, with bounded auto-retry.
    ///
    /// WHY retry here: this load is the app's front door — it races the
    /// radio waking from idle, so a transient failure on attempt one is
    /// common and invisible-to-the-user recovery is worth two quiet retries.
    public func initialPage() async throws -> LoanPage {
        try await RetryPolicy.initialListLoad.execute(sleeper: sleeper) {
            try await repository.fetchLoans(page: 1)
        }
    }

    /// Any subsequent page, no retry.
    ///
    /// WHY no retry: pagination failures surface inline next to a visible
    /// list; the user can scroll again. Stacking automatic retries behind a
    /// scroll gesture just delays the error UI they can already act on.
    public func page(_ index: Int) async throws -> LoanPage {
        try await repository.fetchLoans(page: index)
    }
}
