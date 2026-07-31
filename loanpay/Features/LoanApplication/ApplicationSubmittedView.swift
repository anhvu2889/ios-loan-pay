import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

struct ApplicationSubmittedView: View {
    let receipt: ApplicationReceipt
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Application received")
                .font(.title2.bold())

            Text("Reference \(receipt.applicationID). We'll review it and get back to you within two business days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Done") { onDone() }
                .primaryButton()
        }
        .padding()
        .onAppear {
            AccessibilityNotification.Announcement("Application received.").post()
        }
    }
}

#Preview {
    ApplicationSubmittedView(
        receipt: ApplicationReceipt(applicationID: "app-1234", submittedAt: .now),
        onDone: {}
    )
}
