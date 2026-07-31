import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

struct LoanDetailScreen: View {
    @State private var viewModel: LoanDetailViewModel
    let onMakePayment: () -> Void

    init(viewModel: LoanDetailViewModel, onMakePayment: @escaping () -> Void) {
        // LANG: State(initialValue:) keeps ONE ViewModel per screen
        // identity even though navigationDestination re-invokes its builder
        // on ancestor re-renders — without this, every list update would
        // reset the detail screen to .loading.
        _viewModel = State(initialValue: viewModel)
        self.onMakePayment = onMakePayment
    }

    var body: some View {
        StateContainer(state: displayState, onRetry: { Task { await viewModel.retry() } }) {
            if case .loaded(let detail) = viewModel.state {
                loadedContent(detail)
            }
        }
        .navigationTitle("Loan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var displayState: ContentDisplayState {
        switch viewModel.state {
        case .loading:
            return .loading
        case .loaded:
            return .content
        case .failed(let error):
            return .error(message: error.userMessage, isRetryable: error.isRetryable)
        }
    }

    private func loadedContent(_ detail: LoanDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(detail)
                balanceCard(detail)
                if detail.loan.status != .paidOff {
                    Button("Make a Payment") {
                        onMakePayment()
                    }
                    .primaryButton()
                    .accessibilityIdentifier(AccessibilityID.payButton)
                }
                chartsCard(detail)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func header(_ detail: LoanDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                DeviceImageView(url: detail.loan.deviceImageURL)
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.loan.deviceModel)
                        .font(.title3.bold())
                    StatusBadge(detail.loan.status)
                    Text("Financed since \(detail.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            switch viewModel.freshness {
            case .fresh:
                EmptyView()
            case .cached(let fetchedAt), .staleAfterFailedRefresh(let fetchedAt):
                FreshnessLabel(fetchedAt: fetchedAt, isFromCache: true)
            }
        }
    }

    private func balanceCard(_ detail: LoanDetail) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Outstanding balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(detail.loan.outstandingBalance)
                        .font(.title.bold())
                }
                Divider()
                HStack {
                    labeledAmount("Principal", detail.loan.principal)
                    Spacer()
                    labeledAmount("Monthly", detail.loan.monthlyInstallment)
                    Spacer()
                    if let due = detail.loan.nextInstallmentDue {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next payment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(due.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func labeledAmount(_ label: String, _ money: Money) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountText(money)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func chartsCard(_ detail: LoanDetail) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repayment progress")
                        .font(.headline)
                    RepaymentProgressChart(
                        installments: detail.installments,
                        today: Date()
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Balance over time")
                        .font(.headline)
                    BalanceHistoryChart(history: detail.balanceHistory)
                }
            }
        }
    }
}
