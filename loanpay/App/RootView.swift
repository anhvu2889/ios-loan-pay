import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// The composed application shell: one NavigationStack over the
/// coordinator's typed path.
struct RootView: View {
    private let dependencies: AppDependencies
    @State private var coordinator: AppCoordinator
    @State private var listViewModel: LoanListViewModel
    @State private var isDebugMenuPresented = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // LANG: State(initialValue:) in init — not default-member syntax —
        // because both objects need `dependencies`. SwiftUI keeps the FIRST
        // value it sees for the identity of this view; re-running init on a
        // re-render does not re-create them.
        _coordinator = State(initialValue: AppCoordinator())
        _listViewModel = State(initialValue: dependencies.makeLoanListViewModel())
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.pathBinding) {
            LoanListScreen(
                viewModel: listViewModel,
                onShowDetail: { coordinator.show(.loanDetail($0)) },
                onShowDebugMenu: { isDebugMenuPresented = true }
            )
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

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .loanDetail(let id):
            // Stand-in until the detail feature lands; the ROUTE is already
            // real, so navigation code written now won't change.
            ContentUnavailableView(
                "Loan \(id.rawValue)",
                systemImage: "doc.text",
                description: Text("Detail screen coming in the next slice.")
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
