import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// The sheet's root: renders exactly what the state machine says, nothing
/// else. Every user gesture becomes a `send`.
public struct PaymentFlowView: View {
    @State private var viewModel: PaymentViewModel
    private let onFinished: (PaymentOutcome) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: PaymentViewModel, onFinished: @escaping (PaymentOutcome) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Make a Payment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // WHY no Cancel while paying: dismissal mid-submission
                    // is allowed (drag), but offering a button that races
                    // the charge invites it. The drag path still works and
                    // is handled below.
                    if !isPaying {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { onFinished(.dismissed) }
                        }
                    }
                }
        }
        .interactiveDismissDisabled(isPaying)
        // Haptic on the moment of success — the checkmark you can feel.
        .sensoryFeedback(.success, trigger: isSuccess)
        .onAppear {
            viewModel.send(.start)
        }
        .onDisappear {
            viewModel.send(.dismiss)
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .sessionExpired = newState {
                onFinished(.sessionExpired(returnTo: viewModel.interruptedLoanID))
            }
        }
        .animation(reduceMotion ? nil : .default, value: isSuccess)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Preparing your payment…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loadFailed(let error):
            StateContainer(state: .error(message: error.userMessage, isRetryable: error.isRetryable),
                           onRetry: { viewModel.send(.retry) }) {
                EmptyView()
            }

        case .ready(let context):
            PaymentReadyView(
                context: context,
                isPaying: false,
                errorMessage: nil,
                onSelectMethod: { viewModel.send(.selectMethod($0)) },
                onPay: { viewModel.send(.pay) },
                onRetry: nil
            )

        case .paying(let context):
            PaymentReadyView(
                context: context,
                isPaying: true,
                errorMessage: nil,
                onSelectMethod: { _ in },
                onPay: {},
                onRetry: nil
            )

        case .failed(let context, let error):
            PaymentReadyView(
                context: context,
                isPaying: false,
                errorMessage: error.userMessage,
                onSelectMethod: { viewModel.send(.selectMethod($0)) },
                onPay: {},
                // FINTECH: the button says "Try Again" but the machine
                // resubmits the SAME intent with the SAME key — the copy
                // and the semantics are deliberately different things.
                onRetry: { viewModel.send(.retry) }
            )

        case .sessionExpired:
            // Rendered for the instant before the host tears the sheet
            // down; the app owns re-auth.
            ProgressView()

        case .success(let receipt):
            PaymentSuccessView(receipt: receipt) {
                onFinished(.success)
            }

        case .maintenance:
            PaymentMaintenanceView()
        }
    }

    private var isPaying: Bool {
        if case .paying = viewModel.state { return true }
        return false
    }

    private var isSuccess: Bool {
        if case .success = viewModel.state { return true }
        return false
    }
}

/// How the flow ended, from the host app's point of view.
public enum PaymentOutcome: Sendable {
    case success
    case dismissed
    case sessionExpired(returnTo: LoanID)
}

extension PaymentViewModel {
    /// Where re-auth should return the user: the loan they were paying.
    var interruptedLoanID: LoanID { loanID }
}
