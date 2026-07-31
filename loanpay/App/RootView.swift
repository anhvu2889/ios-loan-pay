import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// The composed application shell: auth phases outside, one
/// NavigationStack over the coordinator's typed path inside.
struct RootView: View {
    private let dependencies: AppDependencies
    @State private var coordinator: AppCoordinator
    @State private var authFlow: AuthFlowCoordinator
    @State private var listViewModel: LoanListViewModel
    @State private var isDebugMenuPresented = false

    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // LANG: State(initialValue:) in init — not default-member syntax —
        // because these objects need `dependencies`. SwiftUI keeps the
        // FIRST value it sees for this view's identity; re-running init on
        // a re-render does not re-create them.
        _coordinator = State(initialValue: AppCoordinator())
        _authFlow = State(initialValue: dependencies.makeAuthFlowCoordinator())
        _listViewModel = State(initialValue: dependencies.makeLoanListViewModel())
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
        .onChange(of: authFlow.phase) { _, newPhase in
            if newPhase == .authenticated,
               let route = coordinator.consumePendingDestination() {
                coordinator.show(route)
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
        #if DEBUG
        .sheet(isPresented: $isDebugMenuPresented) {
            DebugMenuView(behavior: dependencies.mockBehavior, flags: dependencies.flags)
        }
        #endif
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
                    repository: dependencies.loanRepository
                )
            )
        case .applyForLoan:
            ContentUnavailableView(
                "Apply for a loan",
                systemImage: "square.and.pencil",
                description: Text("Application form coming in a later slice.")
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
