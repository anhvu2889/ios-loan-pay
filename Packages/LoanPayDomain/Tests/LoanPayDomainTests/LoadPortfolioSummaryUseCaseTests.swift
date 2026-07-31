import Foundation
import Testing
import LoanPayDomain

@Suite struct LoadPortfolioSummaryUseCaseTests {
    private func loans(_ count: Int) -> [Loan] {
        (1...count).map { Loan.fixture(id: "loan-\($0)") }
    }

    private func quotes(for loans: [Loan], amount: String = "10.00") -> [LoanID: Money] {
        Dictionary(uniqueKeysWithValues: loans.map { ($0.id, Money.usd(amount)) })
    }

    @Test func resultOrderMatchesInputOrderEvenWhenCompletionOrderIsReversed() async throws {
        let input = loans(6)
        let gate = KeyedGate()
        let repository = GatedQuoteRepository(quotes: quotes(for: input), perIDGate: gate)
        let useCase = LoadPortfolioSummaryUseCase(repository: repository)

        // Open per-loan gates in REVERSE so later loans complete first.
        for loan in input.reversed() {
            await gate.open(loan.id.rawValue)
        }

        let summary = try await useCase.summary(for: input, currencyCode: "USD")

        #expect(summary.includedLoanIDs == input.map(\.id))
        #expect(summary.totalOutstanding == .usd("60.00"))
    }

    @Test func failedQuotesDegradeTheSummaryInsteadOfSinkingIt() async throws {
        let input = [
            Loan.fixture(id: "loan-1"),
            Loan.fixture(id: "loan-2", status: .overdue),
            Loan.fixture(id: "loan-3"),
        ]
        let repository = GatedQuoteRepository(
            quotes: quotes(for: input),
            failingIDs: [LoanID("loan-2")]
        )
        let useCase = LoadPortfolioSummaryUseCase(repository: repository)

        let summary = try await useCase.summary(for: input, currencyCode: "USD")

        #expect(summary.totalOutstanding == .usd("20.00"))
        #expect(summary.includedLoanIDs == [LoanID("loan-1"), LoanID("loan-3")])
        #expect(summary.failedLoanIDs == [LoanID("loan-2")])
        #expect(!summary.isComplete)
        #expect(summary.overdueLoanCount == 1)
    }

    @Test func concurrencyIsCappedAtFour() async throws {
        let input = loans(8)
        let gate = Gate()
        let repository = GatedQuoteRepository(quotes: quotes(for: input), entryGate: gate)
        let useCase = LoadPortfolioSummaryUseCase(repository: repository)

        let task = Task {
            try await useCase.summary(for: input, currencyCode: "USD")
        }

        // With the gate shut no fetch can finish, so no fifth fetch can be
        // scheduled — if the cap works, entries stall at exactly 4.
        await gate.waitForEntries(4)
        await Task.yield()
        #expect(await gate.enteredCount == 4)

        await gate.open()
        let summary = try await task.value
        #expect(await gate.enteredCount == 8)
        #expect(summary.totalOutstanding == .usd("80.00"))
        #expect(summary.isComplete)
    }

    @Test func cancellationPropagatesWhileFetchesAreInFlight() async {
        let input = loans(8)
        let gate = Gate()
        let repository = GatedQuoteRepository(quotes: quotes(for: input), entryGate: gate)
        let useCase = LoadPortfolioSummaryUseCase(repository: repository)

        let task = Task {
            try await useCase.summary(for: input, currencyCode: "USD")
        }
        await gate.waitForEntries(4)
        task.cancel()

        let result = await task.result
        #expect(throws: CancellationError.self) {
            try result.get()
        }
    }

    @Test func emptyPortfolioSummarizesToZeroWithoutFetching() async throws {
        let repository = GatedQuoteRepository(quotes: [:])
        let useCase = LoadPortfolioSummaryUseCase(repository: repository)

        let summary = try await useCase.summary(for: [], currencyCode: "USD")

        #expect(summary.totalOutstanding == .zero(currencyCode: "USD"))
        #expect(summary.includedLoanIDs.isEmpty)
        #expect(summary.isComplete)
    }
}
