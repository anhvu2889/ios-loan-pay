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

    /// Which backend this process talks to; fixed at launch.
    let environment: AppEnvironment

    init(environment: AppEnvironment = .current()) {
        self.environment = environment
        let logger = OSAppLogger()
        self.logger = logger
        self.analytics = ConsoleAnalytics()
        self.flags = RuntimeOverridableFlags(base: BundledFeatureFlags())
        let sleeper = ContinuousSleeper()
        self.sleeper = sleeper

        let sessionStore = SessionStore(storage: KeychainWrapper())
        self.sessionStore = sessionStore

        // The behavior actor exists in BOTH environments: the in-process
        // mock consults it for everything; the remote environment still
        // uses it for the outbox deliverer and the application form.
        let behavior = MockBehavior()
        self.mockBehavior = behavior

        // ARCH: the environment switch happens HERE and only here. The SWR
        // decorator wraps whichever base repository the environment picked;
        // screens, caches and use cases cannot tell the difference — that
        // indistinguishability is the whole point of the repository seam.
        let baseLoanRepository: any LoanRepository
        let basePaymentRepository: any PaymentRepository
        switch environment {
        case .mockInProcess:
            baseLoanRepository = MockLoanRepository(behavior: behavior)
            basePaymentRepository = MockPaymentRepository(behavior: behavior)
        case .remoteLocalhost:
            let client = URLSessionAPIClient(
                baseURL: URL(string: "http://localhost:3000")!,
                tokenProvider: { [sessionStore] in await sessionStore.currentToken() },
                logger: logger
            )
            baseLoanRepository = RemoteLoanRepository(client: client)
            basePaymentRepository = RemotePaymentRepository(client: client)
        }

        let cache = CacheStore()
        let cachedRepository = CachedLoanRepository(
            base: baseLoanRepository,
            cache: cache,
            sleeper: sleeper
        )
        self.cacheStore = cache
        self.cachedLoanRepository = cachedRepository
        self.loanRepository = cachedRepository
        self.paymentRepository = basePaymentRepository
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
