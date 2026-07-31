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
    let sessionStore: SessionStore
    let authService: any AuthService
    let biometrics: any BiometricAuthenticating

    init() {
        let logger = OSAppLogger()
        self.logger = logger
        self.analytics = ConsoleAnalytics()
        self.flags = RuntimeOverridableFlags(base: BundledFeatureFlags())
        let sleeper = ContinuousSleeper()
        self.sleeper = sleeper

        // The in-process mock is the runtime default; its behavior actor is
        // kept as a named dependency so the debug menu can inject failures.
        let behavior = MockBehavior()
        self.mockBehavior = behavior
        // ARCH: the SWR decorator wraps the mock exactly as it will wrap
        // the URLSession repository — caching is composed here, invisible
        // to both the data source below and the screens above.
        let cache = CacheStore()
        let cachedRepository = CachedLoanRepository(
            base: MockLoanRepository(behavior: behavior),
            cache: cache,
            sleeper: sleeper
        )
        self.cacheStore = cache
        self.cachedLoanRepository = cachedRepository
        self.loanRepository = cachedRepository
        self.paymentRepository = MockPaymentRepository(behavior: behavior)
        self.connectivity = ConnectivityMonitor()
        // The real outbox replaces the early stub: same OutboxEnqueuing
        // seam, so no feature changed when persistence arrived.
        let outboxStore = OutboxStore()
        self.outboxStore = outboxStore
        self.outbox = outboxStore
        self.outboxDrainer = OutboxDrainer(
            store: outboxStore,
            deliverer: MockOutboxDelivery(behavior: behavior),
            sleeper: sleeper,
            logger: logger
        )

        self.sessionStore = SessionStore(storage: KeychainWrapper())
        self.authService = StubAuthService(sleeper: sleeper)
        self.biometrics = LABiometricAuthenticator(logger: logger)
        self.applicationRepository = MockLoanApplicationRepository(behavior: behavior)
    }

    let applicationRepository: any LoanApplicationRepository
    let cacheStore: CacheStore
    let cachedLoanRepository: CachedLoanRepository
    let connectivity: any ConnectivityMonitoring
    let outboxStore: OutboxStore
    let outboxDrainer: OutboxDrainer

    func makeAuthFlowCoordinator() -> AuthFlowCoordinator {
        AuthFlowCoordinator(
            session: sessionStore,
            biometrics: biometrics,
            logger: logger,
            // FINTECH: the cache is PII (balances, schedules, collateral).
            // It leaves WITH the session — logout and expiry both sweep it.
            onSessionCleared: { [cacheStore] in await cacheStore.removeAll() }
        )
    }

    func makeLoginViewModel(onSuccess: @escaping (String) -> Void) -> LoginViewModel {
        LoginViewModel(authService: authService, onSuccess: onSuccess)
    }

    func makeLoanListViewModel() -> LoanListViewModel {
        LoanListViewModel(
            snapshots: cachedLoanRepository,
            loadLoans: LoadLoansUseCase(repository: loanRepository, sleeper: sleeper),
            loadSummary: LoadPortfolioSummaryUseCase(repository: loanRepository),
            searchRepository: loanRepository,
            connectivity: connectivity,
            outbox: outbox,
            flags: flags,
            logger: logger,
            sleeper: sleeper
        )
    }
}
