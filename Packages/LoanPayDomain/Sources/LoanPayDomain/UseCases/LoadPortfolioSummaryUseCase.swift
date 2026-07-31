import Foundation

/// Aggregates per-loan payoff quotes into one portfolio figure.
public struct LoadPortfolioSummaryUseCase: Sendable {
    // WHY 4: quote fetches are cheap individually but a portfolio can hold
    // dozens of loans. Unbounded fan-out floods the connection pool and, on
    // the real backend, trips per-client rate limits; a cap of 4 keeps the
    // pipe full on LTE without ever stampeding the server.
    private static let maxConcurrentFetches = 4

    private let repository: any LoanRepository

    public init(repository: any LoanRepository) {
        self.repository = repository
    }

    public func summary(for loans: [Loan], currencyCode: String) async throws -> PortfolioSummary {
        let ids = loans.map(\.id)
        var resultsByID: [LoanID: Result<PayoffQuote, DomainError>] = [:]

        // WHY withThrowingTaskGroup: the fetches are structured — they live
        // and die with this scope. If the caller is cancelled, every in-
        // flight quote request is cancelled with it; nothing keeps running
        // after the screen that asked is gone.
        try await withThrowingTaskGroup(of: (LoanID, Result<PayoffQuote, DomainError>).self) { group in
            var pending = ids.makeIterator()

            // WHY the window pattern: seed the group with `maxConcurrent`
            // children, then add one more only as each finishes. The group
            // itself provides the concurrency; the iterator provides the
            // cap. (A semaphore here would block cooperative threads — this
            // shape never blocks, it just doesn't submit yet.)
            for _ in 0..<Self.maxConcurrentFetches {
                guard let id = pending.next() else { break }
                addQuoteTask(for: id, to: &group)
            }

            while let (id, result) = try await group.next() {
                resultsByID[id] = result
                // WHY: check between completions so cancellation is honored
                // promptly even though individual failures are tolerated.
                try Task.checkCancellation()
                if let id = pending.next() {
                    addQuoteTask(for: id, to: &group)
                }
            }
        }

        // WHY assemble from `ids`, not from completion order: quotes finish
        // in whatever order the network decides. Rebuilding from the input
        // sequence makes the summary deterministic — same input, same
        // output — which is what makes it testable and diffable.
        var includedIDs: [LoanID] = []
        var failedIDs: [LoanID] = []
        var amounts: [Money] = []
        for id in ids {
            switch resultsByID[id] {
            case .success(let quote):
                includedIDs.append(id)
                amounts.append(quote.amount)
            case .failure, .none:
                // FINTECH: a failed quote degrades the summary, it does not
                // sink it — the header shows a partial total plus an
                // "incomplete" marker instead of an error screen. The failed
                // ids are carried so the UI can say so honestly.
                failedIDs.append(id)
            }
        }

        return PortfolioSummary(
            totalOutstanding: try Money.sum(amounts, currencyCode: currencyCode),
            overdueLoanCount: loans.count(where: { $0.status == .overdue }),
            includedLoanIDs: includedIDs,
            failedLoanIDs: failedIDs
        )
    }

    private func addQuoteTask(
        for id: LoanID,
        to group: inout ThrowingTaskGroup<(LoanID, Result<PayoffQuote, DomainError>), any Error>
    ) {
        let repository = repository
        group.addTask {
            do {
                return (id, .success(try await repository.fetchPayoffQuote(id: id)))
            } catch let error as CancellationError {
                // WHY rethrow: cancellation is not a per-loan failure to
                // tolerate; it must abort the whole group immediately.
                throw error
            } catch {
                return (id, .failure(error as? DomainError ?? .unknown))
            }
        }
    }
}
