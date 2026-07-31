import Foundation

/// The biometric-gate seam. Throwing means "not verified".
protocol BiometricAuthenticating: Sendable {
    func authenticate(reason: String) async throws
}
