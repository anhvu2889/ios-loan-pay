import Foundation
import Testing
import LoanPayDomain

@Suite struct LoadLoansUseCaseTests {
    @Test func initialPageSucceedsOnSecondAttemptAfterHalfSecondBackoff() async throws {
        let repository = ScriptedLoanRepository(script: [
            .failure(.timeout),
            .success(.fixture(ids: ["loan-1", "loan-2"])),
        ])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        let page = try await useCase.initialPage()

        #expect(page.loans.count == 2)
        await #expect(sleeper.recordedDelays == [.milliseconds(500)])
        await #expect(repository.fetchLoansPages == [1, 1])
    }

    @Test func initialPageSucceedsOnThirdAttemptWithFullBackoffSchedule() async throws {
        let repository = ScriptedLoanRepository(script: [
            .failure(.offline),
            .failure(.serverError(code: 502)),
            .success(.fixture()),
        ])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        _ = try await useCase.initialPage()

        // The exact schedule is part of the contract: 0.5s, then 1s.
        await #expect(sleeper.recordedDelays == [.milliseconds(500), .seconds(1)])
        await #expect(repository.fetchLoansPages == [1, 1, 1])
    }

    @Test func initialPageStopsAfterTwoRetries() async {
        let repository = ScriptedLoanRepository(script: [
            .failure(.timeout),
            .failure(.timeout),
            .failure(.timeout),
        ])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        await #expect(throws: DomainError.timeout) {
            _ = try await useCase.initialPage()
        }
        // 1 attempt + 2 retries, never more.
        await #expect(repository.fetchLoansPages == [1, 1, 1])
    }

    @Test func nonRetryableErrorSurfacesImmediately() async {
        let repository = ScriptedLoanRepository(script: [.failure(.unauthorized)])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        await #expect(throws: DomainError.unauthorized) {
            _ = try await useCase.initialPage()
        }
        await #expect(sleeper.recordedDelays.isEmpty)
        await #expect(repository.fetchLoansPages == [1])
    }

    @Test func cancellationDuringBackoffAbortsTheRetryLoop() async {
        let repository = ScriptedLoanRepository(script: [
            .failure(.timeout),
            .success(.fixture()),
        ])
        let useCase = LoadLoansUseCase(repository: repository, sleeper: CancellingSleeper())

        await #expect(throws: CancellationError.self) {
            _ = try await useCase.initialPage()
        }
        // The second attempt never fires: cancellation wins over retry.
        await #expect(repository.fetchLoansPages == [1])
    }

    @Test func laterPagesNeverRetry() async {
        let repository = ScriptedLoanRepository(script: [.failure(.timeout)])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        await #expect(throws: DomainError.timeout) {
            _ = try await useCase.page(2)
        }
        await #expect(sleeper.recordedDelays.isEmpty)
        await #expect(repository.fetchLoansPages == [2])
    }
}
