import Foundation
import LoanPayDomain
@testable import loanpay

// The app-target test kit: continuation gates and programmable fakes.
// Zero real sleeps — waiting happens on gates the test opens.

let testDate = Date(timeIntervalSince1970: 1_700_000_000)

extension Money {
    static func usd(_ value: String) -> Money {
        Money(amount: Decimal(string: value)!, currencyCode: "USD")
    }
}

extension Loan {
    static func fixture(
        id: String,
        deviceModel: String = "Galaxy A15",
        status: LoanStatus = .active,
        outstanding: String = "100.00"
    ) -> Loan {
        Loan(
            id: LoanID(id),
            deviceModel: deviceModel,
            deviceImageURL: nil,
            principal: .usd("300.00"),
            outstandingBalance: .usd(outstanding),
            monthlyInstallment: .usd("25.00"),
            status: status,
            nextInstallmentDue: testDate
        )
    }
}

/// A gate callers block on until the test opens it (cancellation-aware).
actor Gate {
    private var isOpen = false
    private(set) var enteredCount = 0
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var cancelledIDs: Set<UUID> = []
    private var entryWatchers: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func enter() async throws {
        enteredCount += 1
        notifyEntryWatchers()
        guard !isOpen else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if cancelledIDs.contains(id) {
                    continuation.resume(throwing: CancellationError())
                } else if isOpen {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func open() {
        isOpen = true
        for continuation in waiters.values { continuation.resume() }
        waiters.removeAll()
    }

    func waitForEntries(_ count: Int) async {
        if enteredCount >= count { return }
        await withCheckedContinuation { continuation in
            entryWatchers.append((threshold: count, continuation: continuation))
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledIDs.insert(id)
        }
    }

    private func notifyEntryWatchers() {
        let ready = entryWatchers.filter { $0.threshold <= enteredCount }
        entryWatchers.removeAll { $0.threshold <= enteredCount }
        for watcher in ready { watcher.continuation.resume() }
    }
}

struct InstantSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {}
}

/// Sleeps become gate waits: the debounce window "elapses" when the test
/// opens the gate, and cancellation mid-window behaves exactly like
/// Task.sleep.
struct GateSleeper: Sleeper {
    let gate: Gate

    func sleep(for duration: Duration) async throws {
        try await gate.enter()
    }
}

extension LoanDetail {
    static func fixture(
        id: String = "loan-1",
        status: LoanStatus = .active,
        installmentStatuses: [Installment.Status] = [.paid, .paid, .due, .upcoming]
    ) -> LoanDetail {
        let loan = Loan.fixture(id: id, status: status)
        return LoanDetail(
            loan: loan,
            startDate: testDate,
            installments: installmentStatuses.enumerated().map { index, status in
                Installment(
                    number: index + 1,
                    dueDate: testDate.addingTimeInterval(Double(index) * 86_400 * 30),
                    amount: loan.monthlyInstallment,
                    status: status
                )
            },
            balanceHistory: [
                BalancePoint(date: testDate, balance: loan.principal),
                BalancePoint(date: testDate.addingTimeInterval(86_400 * 30), balance: loan.outstandingBalance),
            ]
        )
    }
}

actor ProgrammableLoanRepository: LoanRepository {
    private var pages: [Int: Result<LoanPage, DomainError>]
    private var pageGates: [Int: Gate] = [:]
    private(set) var pageRequests: [Int] = []
    private(set) var searchQueries: [String] = []
    private var searchResult: [Loan]
    private var detailResult: Result<LoanDetail, DomainError>?
    private(set) var detailRequests: [LoanID] = []

    init(
        pages: [Int: Result<LoanPage, DomainError>],
        searchResult: [Loan] = [],
        detailResult: Result<LoanDetail, DomainError>? = nil
    ) {
        self.pages = pages
        self.searchResult = searchResult
        self.detailResult = detailResult
    }

    func setDetailResult(_ result: Result<LoanDetail, DomainError>) {
        detailResult = result
    }

    func setGate(_ gate: Gate, forPage page: Int) {
        pageGates[page] = gate
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        pageRequests.append(page)
        if let gate = pageGates[page] {
            try await gate.enter()
        }
        guard let scripted = pages[page] else {
            return LoanPage(index: page, loans: [], hasMore: false)
        }
        return try scripted.get()
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        detailRequests.append(id)
        guard let detailResult else { throw DomainError.unknown }
        return try detailResult.get()
    }

    /// Quotes answer with the loan's outstanding balance, mirroring the
    /// mock backend, so summary math is checkable from page fixtures.
    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        for case .success(let page) in pages.values {
            if let loan = page.loans.first(where: { $0.id == id }) {
                return PayoffQuote(loanID: id, amount: loan.outstandingBalance, asOf: testDate)
            }
        }
        throw DomainError.notFound
    }

    func searchLoans(matching query: String) async throws -> [Loan] {
        searchQueries.append(query)
        return searchResult
    }
}

/// Scripted stale-while-revalidate source: yields its snapshots, then
/// finishes (throwing, if an error is scripted).
struct FakeSnapshotProvider: SnapshotLoanReading {
    var pageSnapshots: [Snapshot<LoanPage>] = []
    var pageError: DomainError?
    var detailSnapshots: [Snapshot<LoanDetail>] = []
    var detailError: DomainError?

    func loanPageSnapshots(page: Int) -> AsyncThrowingStream<Snapshot<LoanPage>, any Error> {
        let snapshots = pageSnapshots
        let error = pageError
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish(throwing: error)
        }
    }

    func loanDetailSnapshots(id: LoanID) -> AsyncThrowingStream<Snapshot<LoanDetail>, any Error> {
        let snapshots = detailSnapshots
        let error = detailError
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish(throwing: error)
        }
    }
}

func fresh<V: Sendable>(_ value: V) -> Snapshot<V> {
    Snapshot(value: value, fetchedAt: testDate, isFromCache: false)
}

func cached<V: Sendable>(_ value: V, at date: Date = testDate) -> Snapshot<V> {
    Snapshot(value: value, fetchedAt: date, isFromCache: true)
}

struct FakeConnectivity: ConnectivityMonitoring {
    var statuses: [ConnectivityStatus] = []

    func statusUpdates() -> AsyncStream<ConnectivityStatus> {
        let statuses = statuses
        return AsyncStream { continuation in
            for status in statuses { continuation.yield(status) }
            continuation.finish()
        }
    }
}

actor OutboxSpy: OutboxEnqueuing {
    private(set) var enqueued: [OutboxPayload] = []

    func enqueue(_ payload: OutboxPayload) async throws {
        enqueued.append(payload)
    }
}

struct StubFlags: FeatureFlags {
    var disabled: Set<FeatureFlag> = []

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        !disabled.contains(flag)
    }
}

struct SilentLogger: AppLogger {
    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {}
}
