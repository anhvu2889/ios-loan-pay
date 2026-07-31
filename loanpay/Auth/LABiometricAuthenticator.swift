import Foundation
import LocalAuthentication
import LoanPayDomain

struct LABiometricAuthenticator: BiometricAuthenticating {
    private let logger: any AppLogger

    init(logger: any AppLogger) {
        self.logger = logger
    }

    func authenticate(reason: String) async throws {
        // LANG: LAContext is single-use by design — policy state is cached
        // per instance, so a fresh context per attempt is the correct
        // idiom, not an optimization target.
        let context = LAContext()

        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            // WHY allow-through: `.deviceOwnerAuthentication` already falls
            // back to the device passcode; reaching here means the device
            // has NO passcode at all. Hard-blocking those users locks them
            // out of their own loan data for a bar we cannot raise
            // client-side — the server still authenticates every request.
            // We let them through and record that the gate was skipped
            // (signal, not PII).
            logger.log(.warning, category: .ui, "biometric gate skipped: no device credential enrolled")
            return
        }

        // MODERN: the async evaluatePolicy (iOS 15) replaces the
        // reply-callback + DispatchQueue.main dance; cancellation and
        // errors arrive as thrown LAError instead of a nullable NSError in
        // a closure.
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
