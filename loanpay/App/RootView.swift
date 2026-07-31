import SwiftUI
import LoanPayDomain
import LoanPayData
import LoanPayFeatureKit
import PaymentFeature

/// Identifiable wrapper so `.sheet(item:)` can present a payment for a
/// specific loan.
private struct PaymentSheetContext: Identifiable {
    let loanID: LoanID
    var id: String { loanID.rawValue }
}

/// The composed application shell: auth phases outside, one
/// NavigationStack over the coordinator's typed path inside.
struct RootView: View {
    private let dependencies: AppDependencies
    @State private var coordinator: AppCoordinator
    @State private var authFlow: AuthFlowCoordinator
    @State private var listViewModel: LoanListViewModel
    @State private var dispatcher: DeepLinkDispatcher
    @State private var isDebugMenuPresented = false

    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // LANG: State(initialValue:) in init — not default-member syntax —
        // because these objects need `dependencies`. SwiftUI keeps the
        // FIRST value it sees for this view's identity; re-running init on
        // a re-render does not re-create them.
        _coordinator = State(initialValue: AppCoordinator(logger: dependencies.logger))
        _authFlow = State(initialValue: dependencies.makeAuthFlowCoordinator())
        _listViewModel = State(initialValue: dependencies.makeLoanListViewModel())
        let dispatcher = DeepLinkDispatcher(logger: dependencies.logger)
        FeatureRegistration.registerAll(dispatcher: dispatcher)
        _dispatcher = State(initialValue: dispatcher)
    }

    var body: some View {
        Group {
            switch authFlow.phase {
            case .checking:
                ProgressView()
                    .task { await authFlow.bootstrap() }

            case .loggedOut:
                LoginScreen(viewModel: dependencies.makeLoginViewModel(
                    onSuccess: { token in authFlow.didLogin(token: token) }
                ))

            case .biometricRequired:
                BiometricGateScreen(
                    failureMessage: authFlow.biometricFailureMessage,
                    onAuthenticate: { Task { await authFlow.runBiometricGate() } },
                    onUseDifferentAccount: { Task { await authFlow.logout() } }
                )

            case .authenticated:
                authenticatedShell
            }
        }
        .animation(.default, value: authFlow.phase)
        // FINTECH: the app-switcher snapshot is taken while the scene is
        // inactive. Redacting on ANY non-active phase means balances are
        // already blanked when the system captures it — every AmountText
        // is .privacySensitive, so redaction erases exactly the numbers.
        .redacted(reason: scenePhase == .active ? [] : .privacy)
        .overlay {
            if scenePhase != .active {
                privacyCurtain
            }
        }
        // Deep links arrive here regardless of which auth phase is up.
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onChange(of: authFlow.phase) { _, newPhase in
            if newPhase == .authenticated,
               let intent = coordinator.consumePendingIntent() {
                coordinator.apply(intent)
            }
        }
    }

    private var authenticatedShell: some View {
        @Bindable var coordinator = coordinator
        return NavigationStack(path: $coordinator.pathBinding) {
            LoanListScreen(
                viewModel: listViewModel,
                onShowDetail: { coordinator.show(.loanDetail($0)) },
                onShowDebugMenu: { isDebugMenuPresented = true }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coordinator.show(.applyForLoan)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Apply for a loan")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await authFlow.logout() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .sheet(item: paymentSheetBinding) { context in
            PaymentFeatureEntry.makeFlowView(
                loanID: context.loanID,
                loanRepository: dependencies.loanRepository,
                paymentRepository: dependencies.paymentRepository,
                flags: dependencies.flags,
                analytics: dependencies.analytics,
                logger: dependencies.logger,
                onFinished: { outcome in
                    handlePaymentOutcome(outcome)
                }
            )
        }
        #if DEBUG
        .sheet(isPresented: $isDebugMenuPresented) {
            DebugMenuView(behavior: dependencies.mockBehavior, flags: dependencies.flags)
        }
        #endif
    }

    /// Presentation state lives on the coordinator; this binding only
    /// translates it for `.sheet(item:)` (and routes UI-side dismissal —
    /// the drag gesture — back through the coordinator).
    private var paymentSheetBinding: Binding<PaymentSheetContext?> {
        Binding(
            get: { coordinator.presentedPaymentLoanID.map(PaymentSheetContext.init) },
            set: { newValue in
                if newValue == nil {
                    coordinator.dismissPayment()
                }
            }
        )
    }

    private func handleDeepLink(_ url: URL) {
        let outcome = dispatcher.dispatch(url, isAuthenticated: authFlow.phase == .authenticated)
        switch outcome {
        case .handled(let intent):
            coordinator.apply(intent)
        case .requiresAuth(let intent):
            // Stored, not acted on: the auth flow is already on screen (or
            // will be); the intent fires exactly once on the authenticated
            // transition.
            coordinator.deferUntilAuthenticated(intent)
        case .notRecognized, nil:
            break // logged and dropped by the dispatcher
        }
    }

    private func handlePaymentOutcome(_ outcome: PaymentOutcome) {
        coordinator.dismissPayment()
        switch outcome {
        case .success:
            // FINTECH: unwind STRAIGHT to the list. The consumed
            // confirmation must not be back-reachable, and the detail
            // screen underneath is now stale — landing on the refreshed
            // list is both the safety move and the honest one.
            coordinator.popToRoot()
            Task {
                // The payment changed balances server-side; cached loan
                // data is now a lie and must not outlive the receipt.
                await dependencies.cachedLoanRepository.invalidateLoanData()
                await listViewModel.refresh()
            }

        case .dismissed:
            break

        case .sessionExpired(let loanID):
            // The server said the session is dead mid-payment. Tear down
            // to re-auth, and remember where the user was headed — after
            // login + biometric they land back on that loan.
            coordinator.popToRoot()
            coordinator.deferUntilAuthenticated(
                NavigationIntent(base: .loanList, routes: [.loanDetail(loanID)])
            )
            Task { await authFlow.sessionExpired() }
        }
    }

    private var privacyCurtain: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .loanDetail(let id):
            LoanDetailScreen(
                viewModel: LoanDetailViewModel(
                    loanID: id,
                    snapshots: dependencies.cachedLoanRepository
                ),
                onMakePayment: { coordinator.presentPayment(for: id) }
            )
        case .applyForLoan:
            LoanApplicationScreen(
                viewModel: LoanApplicationViewModel(repository: dependencies.applicationRepository),
                // Done → back to the list; like the payment confirmation,
                // a submitted application is consumed, not revisitable.
                onFinished: { coordinator.popToRoot() }
            )
        case .supportCallback:
            ContentUnavailableView(
                "Support",
                systemImage: "phone",
                description: Text("Support flow coming in a later slice.")
            )
        }
    }
}
