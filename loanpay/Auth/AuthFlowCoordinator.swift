import Foundation
import Observation
import LoanPayDomain

/// Drives the authentication flow: bootstrap → (login) → biometric gate →
/// authenticated.
///
/// ARCH: a coordinator, not a ViewModel — it owns FLOW state (which auth
/// screen exists), while LoginViewModel owns SCREEN state (fields, spinner).
/// The distinction keeps "where am I in the journey" testable without any
/// form logic tagging along.
@Observable
@MainActor
final class AuthFlowCoordinator {
    enum Phase: Equatable {
        case checking
        case loggedOut
        /// A session exists (fresh login or persisted token) but the human
        /// holding the phone has not proven presence yet.
        case biometricRequired
        case authenticated
    }

    private(set) var phase: Phase = .checking
    private(set) var biometricFailureMessage: String?

    private let session: SessionStore
    private let biometrics: any BiometricAuthenticating
    private let logger: any AppLogger
    /// Runs whenever the session ends (logout or expiry): the composition
    /// root hangs the PII sweep here — cached loan data leaves with the
    /// user.
    private let onSessionCleared: () async -> Void
    /// Token from a fresh login, held OUT of the session store until the
    /// biometric gate passes — an interrupted flow must not leave a usable
    /// session behind.
    private var tokenAwaitingGate: String?

    init(
        session: SessionStore,
        biometrics: any BiometricAuthenticating,
        logger: any AppLogger,
        onSessionCleared: @escaping () async -> Void = {}
    ) {
        self.session = session
        self.biometrics = biometrics
        self.logger = logger
        self.onSessionCleared = onSessionCleared
    }

    func bootstrap() async {
        // WHY re-gate a persisted session: the token proves a login
        // happened on this device once; the biometric proves the person
        // holding it NOW is the owner. Loan balances are on the other side
        // of this screen — a found phone must not be enough.
        phase = await session.bootstrap() ? .biometricRequired : .loggedOut
    }

    /// Called by the login screen on stub-login success.
    func didLogin(token: String) {
        tokenAwaitingGate = token
        biometricFailureMessage = nil
        phase = .biometricRequired
    }

    func runBiometricGate() async {
        do {
            try await biometrics.authenticate(reason: "Unlock your loans")
            if let token = tokenAwaitingGate {
                try await session.store(token: token)
                tokenAwaitingGate = nil
            }
            biometricFailureMessage = nil
            phase = .authenticated
        } catch {
            // Stay at the gate; the user can retry or fall back to login.
            // The error is typed for the log, generic for the screen.
            logger.log(.info, category: .ui, "biometric gate failed or was cancelled")
            biometricFailureMessage = "We couldn't verify it's you. Try again."
        }
    }

    func logout() async {
        do {
            try await session.clear()
        } catch {
            // The durable delete failing must not trap the user in a
            // session; memory is cleared regardless and the next launch
            // retries the delete via save-over.
            logger.log(.error, category: .ui, "keychain clear failed during logout")
        }
        tokenAwaitingGate = nil
        await onSessionCleared()
        phase = .loggedOut
    }

    /// The payment flow reports 401s here; session is gone server-side.
    func sessionExpired() async {
        try? await session.clear()
        tokenAwaitingGate = nil
        await onSessionCleared()
        phase = .loggedOut
    }
}
