import Foundation
import LoanPayDomain
@testable import PaymentFeature

let paymentTestDate = Date(timeIntervalSince1970: 1_700_000_000)

func usd(_ value: String) -> Money {
    Money(amount: Decimal(string: value)!, currencyCode: "USD")
}

func makeDetail(id: String = "loan-1", outstanding: String = "140.00") -> LoanDetail {
    let loan = Loan(
        id: LoanID(id),
        deviceModel: "Galaxy A15",
        deviceImageURL: nil,
        principal: usd("240.00"),
        outstandingBalance: usd(outstanding),
        monthlyInstallment: usd("20.00"),
        status: .active,
        nextInstallmentDue: paymentTestDate
    )
    return LoanDetail(loan: loan, startDate: paymentTestDate, installments: [], balanceHistory: [])
}

let testMethods = [
    PaymentMethod(id: PaymentMethodID("pm-1"), displayName: "M-PESA", kind: .mobileWallet),
    PaymentMethod(id: PaymentMethodID("pm-2"), displayName: "Visa", kind: .bankCard),
]

/// Cancellation-aware gate (same shape as the app-target test kit).
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

/// The continuation-gated payment spy: records every submission (and every
/// cancellation), can hold submissions at a gate, and plays back a script
/// of results.
actor SpyPaymentRepository: PaymentRepository {
    private(set) var submissions: [PaymentRequest] = []
    private(set) var cancelledSubmissionCount = 0
    private var submissionScript: [Result<PaymentReceipt, DomainError>]
    private let submitGate: Gate?
    private var methodsScript: [Result<[PaymentMethod], DomainError>]

    init(
        submissionScript: [Result<PaymentReceipt, DomainError>] = [],
        submitGate: Gate? = nil,
        methodsScript: [Result<[PaymentMethod], DomainError>] = [.success(testMethods)]
    ) {
        self.submissionScript = submissionScript
        self.submitGate = submitGate
        self.methodsScript = methodsScript
    }

    func fetchPaymentMethods(for loanID: LoanID) async throws -> [PaymentMethod] {
        let result = methodsScript.count > 1 ? methodsScript.removeFirst() : methodsScript[0]
        return try result.get()
    }

    func submit(_ request: PaymentRequest) async throws -> PaymentReceipt {
        submissions.append(request)
        if let submitGate {
            do {
                try await submitGate.enter()
            } catch is CancellationError {
                cancelledSubmissionCount += 1
                throw CancellationError()
            }
        }
        guard !submissionScript.isEmpty else {
            return Self.receipt(for: request)
        }
        return try submissionScript.removeFirst().get()
    }

    static func receipt(for request: PaymentRequest) -> PaymentReceipt {
        PaymentReceipt(
            paymentID: "pay-\(request.idempotencyKey.value.prefix(8))",
            loanID: request.loanID,
            amountPaid: request.amount,
            remainingBalance: usd("120.00"),
            processedAt: paymentTestDate
        )
    }
}

actor StubLoanRepository: LoanRepository {
    private let detailResult: Result<LoanDetail, DomainError>
    private(set) var detailFetchCount = 0

    init(detailResult: Result<LoanDetail, DomainError> = .success(makeDetail())) {
        self.detailResult = detailResult
    }

    func fetchLoans(page: Int) async throws -> LoanPage {
        throw DomainError.unknown
    }

    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        detailFetchCount += 1
        return try detailResult.get()
    }

    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        throw DomainError.unknown
    }

    func searchLoans(matching query: String) async throws -> [Loan] {
        throw DomainError.unknown
    }
}

struct TestFlags: FeatureFlags {
    var paymentsEnabled = true

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        flag == .paymentsEnabled ? paymentsEnabled : true
    }
}

/// Thread-safe recording analytics for funnel assertions.
final class RecordingAnalytics: AnalyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.withLock { _events }
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock { _events.append(event) }
    }
}

struct NullLogger: AppLogger {
    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {}
}
