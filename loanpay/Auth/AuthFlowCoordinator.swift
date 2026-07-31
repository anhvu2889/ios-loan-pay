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
    /// How long the app may sit backgrounded before the session dies.
    private let inactivityTimeout: TimeInterval
    private var backgroundedAt: Date?
    /// Token from a fresh login, held OUT of the session store until the
    /// biometric gate passes — an interrupted flow must not leave a usable
    /// session behind.
    private var tokenAwaitingGate: String?

    init(
        session: SessionStore,
        biometrics: any BiometricAuthenticating,
        logger: any AppLogger,
        inactivityTimeout: TimeInterval = 5 * 60
    ) {
        self.session = session
        self.biometrics = biometrics
        self.logger = logger
        self.inactivityTimeout = inactivityTimeout
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
        tokenAwaitingGate = nil
        await session.clearAll()
        phase = .loggedOut
    }

    /// The payment flow reports 401s here; session is gone server-side.
    func sessionExpired() async {
        tokenAwaitingGate = nil
        await session.clearAll()
        phase = .loggedOut
    }

    // MARK: - Inactivity timeout

    func sceneDidEnterBackground(at date: Date = Date()) {
        guard phase == .authenticated else { return }
        backgroundedAt = date
    }

    /// FINTECH: a phone that sat on a counter for five minutes is a phone
    /// whose holder we no longer know. Past the timeout the session is
    /// CLEARED (token + PII sweep, same path as a server-side 401), not
    /// merely re-gated — and re-entry runs the full login + biometric
    /// flow. Short foreground hops (< timeout) cost the user nothing.
    func sceneDidBecomeActive(at date: Date = Date()) async {
        defer { backgroundedAt = nil }
        guard phase == .authenticated,
              let backgroundedAt,
              date.timeIntervalSince(backgroundedAt) >= inactivityTimeout else {
            return
        }
        logger.log(.info, category: .ui, "session ended by inactivity timeout")
        await sessionExpired()
    }
}
