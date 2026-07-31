import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// The ready/paying/failed face of the flow — same layout, three moods.
///
/// ARCH: values and closures only. `isPaying` and `errorMessage` are
/// PROJECTIONS of the state machine, computed by the flow view; this view
/// could not corrupt the machine if it tried.
struct PaymentReadyView: View {
    let context: PaymentContext
    let isPaying: Bool
    let errorMessage: String?
    let onSelectMethod: (PaymentMethodID) -> Void
    let onPay: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(context.detail.loan.deviceModel)
                        .font(.headline)
                    HStack {
                        Text("Payment due")
                            .foregroundStyle(.secondary)
                        Spacer()
                        AmountText(context.amount)
                            .font(.title2.bold())
                    }
                    HStack {
                        Text("Balance after payment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let projected = try? context.detail.loan.outstandingBalance
                            .adding(Money(amount: -context.amount.amount, currencyCode: context.amount.currencyCode)) {
                            AmountText(projected)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pay with")
                    .font(.subheadline.weight(.semibold))
                ForEach(context.methods) { method in
                    PaymentMethodRow(
                        method: method,
                        isSelected: method.id == context.selectedMethodID,
                        onSelect: { onSelectMethod(method.id) }
                    )
                    .disabled(isPaying)
                }
            }
            .accessibilityIdentifier(AccessibilityID.paymentMethodPicker)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            if let onRetry {
                Button("Try Again") { onRetry() }
                    .primaryButton()
                    .accessibilityIdentifier(AccessibilityID.paymentRetryButton)
            } else {
                Button(isPaying ? "Paying…" : "Pay \(context.amount.formatted())") {
                    onPay()
                }
                .primaryButton(isLoading: isPaying)
                .accessibilityIdentifier(AccessibilityID.payButton)
                // The spoken label uses currency words, not the symbol.
                .accessibilityLabel(isPaying ? "Paying" : "Pay \(context.amount.spokenDescription())")
            }
        }
        .padding()
    }
}

private struct PaymentMethodRow: View {
    let method: PaymentMethod
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 28)
                Text(method.displayName)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var icon: String {
        switch method.kind {
        case .bankCard: "creditcard"
        case .mobileWallet: "iphone.radiowaves.left.and.right"
        case .cashAgent: "person.crop.circle.badge.checkmark"
        }
    }
}

#Preview("Ready") {
    PaymentReadyView(
        context: PaymentContext(
            detail: LoanDetail(
                loan: PreviewFixtures.activeLoan,
                startDate: .now,
                installments: [],
                balanceHistory: []
            ),
            methods: PreviewFixtures.paymentMethods
        ),
        isPaying: false,
        errorMessage: nil,
        onSelectMethod: { _ in },
        onPay: {},
        onRetry: nil
    )
}

#Preview("Failed, dark, large type") {
    PaymentReadyView(
        context: PaymentContext(
            detail: LoanDetail(
                loan: PreviewFixtures.overdueLoan,
                startDate: .now,
                installments: [],
                balanceHistory: []
            ),
            methods: PreviewFixtures.paymentMethods
        ),
        isPaying: false,
        errorMessage: "This is taking longer than expected. Please try again.",
        onSelectMethod: { _ in },
        onPay: {},
        onRetry: {}
    )
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
