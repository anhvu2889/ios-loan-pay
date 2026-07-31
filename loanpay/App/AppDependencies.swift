import Foundation
import LoanPayDomain
import LoanPayData

/// The composition root: the ONE place concrete types meet.
///
/// ARCH: everything below the app target speaks in protocols; this class is
/// where MockLoanRepository becomes "the" LoanRepository, where the logger
/// gains an OS backend, where flags gain a bundle. Swapping the data source
/// (mock → remote) or any cross-cutting service is an edit HERE, invisible
/// to every feature.
@MainActor
final class AppDependencies {
    let logger: any AppLogger
    let analytics: any AnalyticsClient
    let flags: RuntimeOverridableFlags
    let mockBehavior: MockBehavior
    let loanRepository: any LoanRepository
    let paymentRepository: any PaymentRepository
    let outbox: any OutboxEnqueuing
    let sleeper: any Sleeper

    init() {
        let logger = OSAppLogger()
        self.logger = logger
        self.analytics = ConsoleAnalytics()
        self.flags = RuntimeOverridableFlags(base: BundledFeatureFlags())
        self.sleeper = ContinuousSleeper()

        // The in-process mock is the runtime default; its behavior actor is
        // kept as a named dependency so the debug menu can inject failures.
        let behavior = MockBehavior()
        self.mockBehavior = behavior
        self.loanRepository = MockLoanRepository(behavior: behavior)
        self.paymentRepository = MockPaymentRepository(behavior: behavior)
        self.outbox = LoggedOutboxStub(logger: logger)
    }

    func makeLoanListViewModel() -> LoanListViewModel {
        LoanListViewModel(
            loadLoans: LoadLoansUseCase(repository: loanRepository, sleeper: sleeper),
            loadSummary: LoadPortfolioSummaryUseCase(repository: loanRepository),
            searchRepository: loanRepository,
            outbox: outbox,
            flags: flags,
            logger: logger,
            sleeper: sleeper
        )
    }
}
