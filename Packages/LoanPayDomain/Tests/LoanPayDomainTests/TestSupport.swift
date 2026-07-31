import Foundation
import LoanPayDomain

// WHY this file: the suite runs with ZERO real sleeps. Time and concurrency
// are made deterministic with two tools — recording sleepers (delays are
// data, not waiting) and continuation gates (tasks block until the test
// says go). Every async test in this package is built from these.

let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)

extension Money {
    static func usd(_ value: String) -> Money {
        Money(amount: Decimal(string: value)!, currencyCode: "USD")
    }
}

extension Loan {
    static func fixture(
        id: String = "loan-1",
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
            nextInstallmentDue: fixtureDate
        )
    }
}

extension LoanPage {
    static func fixture(index: Int = 1, ids: [String] = ["loan-1"], hasMore: Bool = false) -> LoanPage {
        LoanPage(index: index, loans: ids.map { Loan.fixture(id: $0) }, hasMore: hasMore)
    }
}

/// Records requested delays and returns immediately — backoff becomes an
/// assertable value instead of wall-clock time.
actor RecordingSleeper: Sleeper {
    private(set) var recordedDelays: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDelays.append(duration)
    }
}

/// Simulates a task being cancelled while parked in a backoff sleep.
struct CancellingSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {
        throw CancellationError()
    }
}

/// A gate every caller blocks on until the test opens it. Counts entries so
/// tests can wait for "exactly N tasks are inside" without polling.
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
        // WHY the cancelledIDs bookkeeping: onCancel is synchronous and may
        // run before the continuation is stored. Recording the id lets the
        // store-side detect "already cancelled" and resume immediately —
        // without it a cancelled waiter would hang forever.
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

    /// Suspends until at least `count` callers have entered.
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

/// Per-key gate: `wait(for:)` blocks until that key is opened. Opening a key
/// before anyone waits is allowed — late waiters pass straight through.
actor KeyedGate {
    private var openedKeys: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func wait(for key: String) async {
        if openedKeys.contains(key) { return }
        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    func open(_ key: String) {
        openedKeys.insert(key)
        waiters.removeValue(forKey: key)?.forEach { $0.resume() }
    }
}

/// Plays back a per-call script for `fetchLoans` and records every call.
actor ScriptedLoanRepository: LoanRepository {
    private var firstPageScript: [Result<LoanPage, DomainError>]
    private(set) var fetchLoansPages: [Int] = []

    init(script: [Result<LoanPage, DomainError>]) {
        self.firstPageScript = script
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        fetchLoansPages.append(page)
        guard !firstPageScript.isEmpty else { return .fixture(index: page) }
        return try firstPageScript.removeFirst().get()
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        throw DomainError.unknown
    }

    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        throw DomainError.unknown
    }

    func searchLoans(matching query: String) async throws -> [Loan] {
        throw DomainError.unknown
    }
}

/// Payoff quotes controlled by gates: an optional shared entry gate (for
/// concurrency-cap and cancellation tests) and an optional per-id gate (to
/// force out-of-order completion).
actor GatedQuoteRepository: LoanRepository {
    private let quotes: [LoanID: Money]
    private let failingIDs: Set<LoanID>
    private let entryGate: Gate?
    private let perIDGate: KeyedGate?

    init(
        quotes: [LoanID: Money],
        failingIDs: Set<LoanID> = [],
        entryGate: Gate? = nil,
        perIDGate: KeyedGate? = nil
    ) {
        self.quotes = quotes
        self.failingIDs = failingIDs
        self.entryGate = entryGate
        self.perIDGate = perIDGate
    }

    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        try await entryGate?.enter()
        await perIDGate?.wait(for: id.rawValue)
        if failingIDs.contains(id) { throw DomainError.serverError(code: 500) }
        guard let amount = quotes[id] else { throw DomainError.notFound }
        return PayoffQuote(loanID: id, amount: amount, asOf: fixtureDate)
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        throw DomainError.unknown
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        throw DomainError.unknown
    }

    func searchLoans(matching query: String) async throws -> [Loan] {
        throw DomainError.unknown
    }
}
