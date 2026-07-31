import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct MockLoanRepositoryTests {
    @Test func paginationServesAtLeastThreePagesAndTerminates() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())

        var pages: [LoanPage] = []
        var index = 1
        while true {
            let page = try await repository.fetchLoans(page: index)
            pages.append(page)
            if !page.hasMore { break }
            index += 1
        }

        #expect(pages.count >= 3)
        #expect(pages.dropLast().allSatisfy { $0.hasMore })
        #expect(pages.last?.hasMore == false)
        // No loan appears on two pages, none is lost.
        let allIDs = pages.flatMap { $0.loans.map(\.id) }
        #expect(Set(allIDs).count == allIDs.count)
        #expect(allIDs.count == 25)
    }

    @Test func pageBeyondTheEndIsEmptyAndFinal() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        let page = try await repository.fetchLoans(page: 99)
        #expect(page.loans.isEmpty)
        #expect(!page.hasMore)
    }

    @Test func injectedOfflineSurfacesAsDomainOffline() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.offline, for: .loanList)
        let repository = makeLoanRepository(behavior: behavior)

        await #expect(throws: DomainError.offline) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func injectedMalformedJSONTravelsTheDecodePath() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.malformedJSON, for: .loanList)
        let repository = makeLoanRepository(behavior: behavior)

        do {
            _ = try await repository.fetchLoans(page: 1)
            Issue.record("expected invalidData")
        } catch let error as DomainError {
            guard case .invalidData = error else {
                Issue.record("expected invalidData, got \(error)")
                return
            }
        }
    }

    @Test func injectedStatusMapsThroughErrorMapper() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.httpStatus(503), for: .loanList)
        let repository = makeLoanRepository(behavior: behavior)

        await #expect(throws: DomainError.serverError(code: 503)) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func failureInjectionIsScopedToItsEndpoint() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.offline, for: .loanDetail)
        let repository = makeLoanRepository(behavior: behavior)

        // The list keeps working while detail fails — outages are per-path.
        _ = try await repository.fetchLoans(page: 1)
        await #expect(throws: DomainError.offline) {
            _ = try await repository.fetchLoanDetail(id: LoanID("loan-001"))
        }
    }

    @Test func unknownLoanIDMapsToNotFound() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        await #expect(throws: DomainError.notFound) {
            _ = try await repository.fetchLoanDetail(id: LoanID("loan-999"))
        }
    }

    @Test func searchFiltersByDeviceModelCaseInsensitively() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        let results = try await repository.searchLoans(matching: "galaxy")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.deviceModel.localizedCaseInsensitiveContains("galaxy") })
    }

    @Test func blankSearchReturnsNothing() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        #expect(try await repository.searchLoans(matching: "   ").isEmpty)
    }

    @Test func simulatedLatencyGoesThroughTheInjectedSleeper() async throws {
        let sleeper = RecordingSleeper()
        let behavior = MockBehavior(latency: .milliseconds(400))
        let repository = makeLoanRepository(behavior: behavior, sleeper: sleeper)

        _ = try await repository.fetchLoans(page: 1)

        // The mock *requested* 400ms but this test finished instantly —
        // latency is data through the Sleeper seam, not wall-clock time.
        await #expect(sleeper.recordedDelays == [.milliseconds(400)])
    }

    @Test func slowInjectionAddsItsDelayThroughTheSleeper() async throws {
        let sleeper = RecordingSleeper()
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.slow(seconds: 3), for: .loanList)
        let repository = makeLoanRepository(behavior: behavior, sleeper: sleeper)

        _ = try await repository.fetchLoans(page: 1)

        await #expect(sleeper.recordedDelays == [.zero, .milliseconds(3000)])
    }

    @Test func flakyAtFullRateAlwaysFails() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.flaky(rate: 1.0), for: .loanList)
        let repository = makeLoanRepository(behavior: behavior)

        await #expect(throws: DomainError.offline) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func flakyAtZeroRateNeverFails() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.flaky(rate: 0.0), for: .loanList)
        let repository = makeLoanRepository(behavior: behavior)

        _ = try await repository.fetchLoans(page: 1)
    }

    @Test func fixtureContainsAnUnknownStatusLoanForForwardCompatibility() async throws {
        let repository = makeLoanRepository(behavior: makeInstantBehavior())
        var loans: [Loan] = []
        var index = 1
        while true {
            let page = try await repository.fetchLoans(page: index)
            loans += page.loans
            if !page.hasMore { break }
            index += 1
        }
        #expect(loans.contains { $0.status == .unknown })
    }
}
