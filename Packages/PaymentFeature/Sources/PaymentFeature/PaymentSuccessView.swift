import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

struct PaymentSuccessView: View {
    let receipt: PaymentReceipt
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: receipt.paymentID)

            Text("Payment complete")
                .font(.title2.bold())

            VStack(spacing: 6) {
                AmountText(receipt.amountPaid)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    Text("Remaining balance:")
                        .foregroundStyle(.secondary)
                    AmountText(receipt.remainingBalance)
                }
                .font(.subheadline)
            }

            Spacer()

            // FINTECH: "Done" unwinds STRAIGHT to the loan list — the
            // confirmation is consumed and must not be back-reachable.
            // A back-navigable success screen with a Pay button one tap
            // away is a double-payment invitation; navigation itself is
            // the re-submission defense here, on top of the idempotency
            // key.
            Button("Done") { onDone() }
                .primaryButton()
        }
        .padding()
        .onAppear {
            // MODERN: AccessibilityNotification (iOS 17) replaces
            // UIAccessibility.post(notification:argument:). The outcome is
            // announced immediately — a VoiceOver user must not have to go
            // hunting to learn their money moved.
            AccessibilityNotification.Announcement(
                "Payment complete. \(receipt.amountPaid.spokenDescription()) paid."
            ).post()
        }
    }
}

#Preview("Success") {
    PaymentSuccessView(
        receipt: PaymentReceipt(
            paymentID: "pay-1",
            loanID: PreviewFixtures.activeLoan.id,
            amountPaid: PreviewFixtures.activeLoan.monthlyInstallment,
            remainingBalance: PreviewFixtures.activeLoan.outstandingBalance,
            processedAt: .now
        ),
        onDone: {}
    )
}
