import XCTest
import LoanPayDomain
@testable import LoanPayData

// Twelve representative tests from the Swift Testing suite of record,
// translated to XCTest. Read with XCTestPrimer.swift open. Each test names
// its original.

// MARK: - Local test doubles (mirrors of the originals' fakes)

private actor RecordingSleeper: Sleeper {
    private(set) var recordedDelays: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDelays.append(duration)
    }
}

private actor ScriptedLoanRepository: LoanRepository {
    private var script: [Result<LoanPage, DomainError>]
    private(set) var calls = 0

    init(script: [Result<LoanPage, DomainError>]) {
        self.script = script
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        calls += 1
        guard !script.isEmpty else { return LoanPage(index: page, loans: [], hasMore: false) }
        return try script.removeFirst().get()
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail { throw DomainError.unknown }
    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote { throw DomainError.unknown }
    func searchLoans(matching query: String) async throws -> [Loan] { throw DomainError.unknown }
}

private actor FailingDeliverer: OutboxDelivering {
    private(set) var attempts: [OutboxOperation] = []

    func deliver(_ operation: OutboxOperation) async throws {
        attempts.append(operation)
        throw DomainError.offline
    }
}

private final class SpyDisk: CacheDisk, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private(set) var readCount = 0

    func read(key: String) -> Data? {
        lock.withLock { readCount += 1; return storage[key] }
    }

    func write(key: String, data: Data) {
        lock.withLock { storage[key] = data }
    }

    func delete(key: String) {
        lock.withLock { storage[key] = nil }
    }

    func deleteAll() {
        lock.withLock { storage.removeAll() }
    }
}

private struct NullLogger: AppLogger {
    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {}
}

private func usd(_ value: String) -> Money {
    Money(amount: Decimal(string: value)!, currencyCode: "USD")
}

// ROSETTA: `final class ... : XCTestCase` replaces `@Suite struct`. Methods
// run SERIALLY; a fresh instance exists per test method, so these instance-
// less helpers behave the same as the struct originals.
final class RosettaTests: XCTestCase {
    // 1. Original: MoneyTests.decimalAdditionIsExact
    // ROSETTA: XCTAssertEqual replaces #expect(==). The Double failure the
    // original documents holds here too: XCTAssertEqual(0.1 + 0.2, 0.3)
    // on Doubles FAILS without an accuracy: parameter — which is itself
    // the lesson.
    func testDecimalAdditionIsExact() throws {
        let sum = try usd("0.10").adding(usd("0.20"))
        XCTAssertEqual(sum, usd("0.30"))
    }

    // 2. Original: MoneyTests.mixedCurrencyAdditionRefuses
    // ROSETTA: XCTAssertThrowsError takes the throwing expression and hands
    // the error to a closure for further asserts — the shape #expect(
    // throws:) gives you in one line.
    func testMixedCurrencyAdditionRefuses() {
        let kes = Money(amount: 100, currencyCode: "KES")
        XCTAssertThrowsError(try usd("1.00").adding(kes)) { error in
            XCTAssertEqual(error as? DomainError, .invalidData(keyPath: "Money.currencyCode"))
        }
    }

    // 3. Original: LoadLoansUseCaseTests.initialPageSucceedsOnThirdAttemptWithFullBackoffSchedule
    // ROSETTA: async test methods look identical in both frameworks —
    // XCTest gained async support in Xcode 13; no expectation needed.
    func testInitialPageRetriesWithExactBackoffSchedule() async throws {
        let repository = ScriptedLoanRepository(script: [
            .failure(.offline),
            .failure(.serverError(code: 502)),
            .success(LoanPage(index: 1, loans: [], hasMore: false)),
        ])
        let sleeper = RecordingSleeper()
        let useCase = LoadLoansUseCase(repository: repository, sleeper: sleeper)

        _ = try await useCase.initialPage()

        let delays = await sleeper.recordedDelays
        XCTAssertEqual(delays, [.milliseconds(500), .seconds(1)])
        let calls = await repository.calls
        XCTAssertEqual(calls, 3)
    }

    // 4. Original: LoadLoansUseCaseTests.nonRetryableErrorSurfacesImmediately
    // ROSETTA: no async XCTAssertThrowsError exists — the do/catch with
    // XCTFail in the success arm is the standard translation.
    func testNonRetryableErrorSurfacesImmediately() async {
        let repository = ScriptedLoanRepository(script: [.failure(.unauthorized)])
        let useCase = LoadLoansUseCase(repository: repository, sleeper: RecordingSleeper())

        do {
            _ = try await useCase.initialPage()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? DomainError, .unauthorized)
        }
        let calls = await repository.calls
        XCTAssertEqual(calls, 1)
    }

    // 5. Original: ErrorMapperTests.offlineURLErrorsMapToOffline
    // ROSETTA: the original is @Test(arguments:); XCTest has no
    // parameterized tests, so the idiomatic form is a loop — one test, N
    // asserts, each with enough message context to identify the failing
    // case.
    func testOfflineURLErrorsMapToOffline() {
        for code in [URLError.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed] {
            XCTAssertEqual(
                ErrorMapper.domainError(from: URLError(code)),
                .offline,
                "URLError \(code) should map to .offline"
            )
        }
    }

    // 6. Original: ErrorMapperTests.decodingErrorCarriesKeyPathOnly
    func testDecodingErrorCarriesKeyPathOnly() {
        struct Probe: Decodable { let loan: Inner }
        struct Inner: Decodable { let balance: String }

        do {
            _ = try JSONDecoder().decode(Probe.self, from: Data(#"{"loan": {"balance": 42}}"#.utf8))
            XCTFail("decode should have failed")
        } catch {
            XCTAssertEqual(ErrorMapper.domainError(from: error), .invalidData(keyPath: "loan.balance"))
        }
    }

    // 7. Original: MockLoanRepositoryTests.paginationServesAtLeastThreePagesAndTerminates
    // ROSETTA: `try XCTUnwrap` replaces `try #require` for optionals; note
    // it aborts THIS test on failure, same as #require (see primer §2).
    func testPaginationIntegrity() async throws {
        let repository = MockLoanRepository(behavior: MockBehavior(latency: .zero))

        var pages: [LoanPage] = []
        var index = 1
        while true {
            let page = try await repository.fetchLoans(page: index)
            pages.append(page)
            if !page.hasMore { break }
            index += 1
        }

        XCTAssertGreaterThanOrEqual(pages.count, 3)
        let last = try XCTUnwrap(pages.last)
        XCTAssertFalse(last.hasMore)
        let ids = pages.flatMap { $0.loans.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count, "no loan may appear on two pages")
    }

    // 8. Original: MockPaymentRepositoryTests.replayedIdempotencyKeyReturnsTheOriginalReceipt
    func testIdempotentReplayReturnsOriginalReceipt() async throws {
        let repository = MockPaymentRepository(
            behavior: MockBehavior(latency: .zero),
            sleeper: RecordingSleeper()
        )
        let key = IdempotencyKey.generate()
        let request = PaymentRequest(
            loanID: LoanID("loan-001"),
            methodID: PaymentMethodID("pm-wallet-mpesa"),
            amount: usd("20.00"),
            idempotencyKey: key
        )

        let first = try await repository.submit(request)
        let replay = try await repository.submit(request)

        XCTAssertEqual(replay, first, "same key must surface the settled receipt, not a second charge")
    }

    // 9. Original: CacheStoreTests.roundTripsValuesWithTheirFetchTime
    func testCacheRoundTripsValueAndTimestamp() async {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let store = CacheStore(disk: SpyDisk(), now: { stamp })
        let page = LoanPage(index: 1, loans: [], hasMore: false)

        await store.store(page, forKey: "k")
        let hit = await store.load(LoanPage.self, forKey: "k")

        XCTAssertEqual(hit?.value, page)
        XCTAssertEqual(hit?.fetchedAt, stamp)
    }

    // 10. Original: TwoTierCacheTests.memoryHitNeverTouchesDisk
    func testMemoryHitNeverTouchesDisk() async {
        let disk = SpyDisk()
        let store = CacheStore(disk: disk)

        await store.store(LoanPage(index: 1, loans: [], hasMore: false), forKey: "k")
        _ = await store.load(LoanPage.self, forKey: "k")
        _ = await store.load(LoanPage.self, forKey: "k")

        XCTAssertEqual(disk.readCount, 0, "both loads must be memory hits")
    }

    // 11. Original: OutboxDrainerTests.operationParksAsFailedAfterMaxAttempts
    func testOutboxOperationParksAsFailedAfterMaxAttempts() async throws {
        let store = OutboxStore(directoryName: "Rosetta-\(UUID().uuidString)")
        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))
        let deliverer = FailingDeliverer()
        let drainer = OutboxDrainer(
            store: store,
            deliverer: deliverer,
            sleeper: RecordingSleeper(),
            logger: NullLogger(),
            maxAttempts: 3
        )

        await drainer.drainNow()

        let attempts = await deliverer.attempts
        XCTAssertEqual(attempts.count, 3)
        let stats = await store.currentStats()
        XCTAssertEqual(stats.failedCount, 1)
        XCTAssertEqual(stats.pendingCount, 0)
    }

    // 12. Original: OutboxDrainerTests.retriesReuseTheSameIdempotencyKey
    func testOutboxRetriesReuseTheSameIdempotencyKey() async throws {
        let store = OutboxStore(directoryName: "Rosetta-\(UUID().uuidString)")
        try await store.enqueue(.supportCallback(topic: "device", loanID: nil))
        let deliverer = FailingDeliverer()
        let drainer = OutboxDrainer(
            store: store,
            deliverer: deliverer,
            sleeper: RecordingSleeper(),
            logger: NullLogger(),
            maxAttempts: 3
        )

        await drainer.drainNow()

        let keys = await deliverer.attempts.map(\.idempotencyKey)
        XCTAssertEqual(Set(keys).count, 1, "every attempt must present the same bytes")
    }

    // BONUS — the deliberate legacy example.
    // Original: OutboxStoreTests.statsStreamPushesOnMutation
    // ROSETTA: XCTestExpectation, kept as the ONE sanctioned specimen (see
    // primer §3). The original just iterates the stream with `await`;
    // this form exists for shapes plain await can't express — here,
    // "an update arrives WHILE the test is busy doing something else."
    // fulfillment(of:) is the async-aware wait; the timeout is a
    // last-resort tripwire, not a synchronization tool.
    func testStatsStreamPushesOnMutation_legacyExpectationStyle() async throws {
        let store = OutboxStore(directoryName: "Rosetta-\(UUID().uuidString)")
        let sawPendingUpdate = expectation(description: "stats stream pushed pending=1")

        let stream = await store.statsUpdates()
        let observer = Task {
            for await stats in stream where stats.pendingCount == 1 {
                sawPendingUpdate.fulfill()
                break
            }
        }

        try await store.enqueue(.supportCallback(topic: "billing", loanID: nil))

        await fulfillment(of: [sawPendingUpdate], timeout: 5)
        observer.cancel()
    }
}
