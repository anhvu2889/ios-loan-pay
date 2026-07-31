import SwiftUI
import LoanPayFeatureKit

/// The presence check between "a session exists" and "show balances".
struct BiometricGateScreen: View {
    let failureMessage: String?
    let onAuthenticate: () -> Void
    let onUseDifferentAccount: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Unlock LoanPay")
                .font(.title2.bold())
            Text("Confirm it's you to see your loans and make payments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let failureMessage {
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Unlock") {
                onAuthenticate()
            }
            .primaryButton()

            Button("Use a different account") {
                onUseDifferentAccount()
            }
            .font(.subheadline)

            Spacer()
        }
        .padding(24)
        // WHY auto-trigger: the gate should feel like the OS unlocking, not
        // a screen demanding a tap. The button remains for retries.
        .task {
            onAuthenticate()
        }
    }
}
