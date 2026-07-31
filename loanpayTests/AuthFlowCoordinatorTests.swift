import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

/// Scripted biometric gate: pass or fail on demand, attempts counted.
final class FakeBiometrics: BiometricAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var shouldSucceed: Bool
    private(set) var attempts = 0

    init(shouldSucceed: Bool) {
        self.shouldSucceed = shouldSucceed
    }

    func setShouldSucceed(_ value: Bool) {
        lock.withLock { shouldSucceed = value }
    }

    func authenticate(reason: String) async throws {
        let succeed: Bool = lock.withLock {
            attempts += 1
            return shouldSucceed
        }
        if !succeed {
            throw DomainError.unauthorized
        }
    }
}

@MainActor
@Suite struct AuthFlowCoordinatorTests {
    private func makeCoordinator(
        storage: InMemoryTokenStorage = InMemoryTokenStorage(),
        biometrics: FakeBiometrics = FakeBiometrics(shouldSucceed: true)
    ) -> (AuthFlowCoordinator, SessionStore, InMemoryTokenStorage) {
        let session = SessionStore(storage: storage)
        let coordinator = AuthFlowCoordinator(
            session: session,
            biometrics: biometrics,
            logger: SilentLogger()
        )
        return (coordinator, session, storage)
    }

    @Test func bootstrapWithoutSessionLandsOnLogin() async {
        let (coordinator, _, _) = makeCoordinator()
        await coordinator.bootstrap()
        #expect(coordinator.phase == .loggedOut)
    }

    @Test func bootstrapWithPersistedSessionStillRequiresTheGate() async {
        let (coordinator, _, _) = makeCoordinator(storage: InMemoryTokenStorage(token: "persisted"))
        await coordinator.bootstrap()
        // A stored token is NOT enough to see balances — presence first.
        #expect(coordinator.phase == .biometricRequired)
    }

    @Test func freshLoginStoresTheTokenOnlyAfterTheGatePasses() async throws {
        let (coordinator, session, storage) = makeCoordinator()
        await coordinator.bootstrap()

        coordinator.didLogin(token: "fresh-token")
        #expect(coordinator.phase == .biometricRequired)
        // The token must NOT be persisted yet — an abandoned gate must not
        // leave a usable session on the device.
        #expect(try storage.load() == nil)

        await coordinator.runBiometricGate()

        #expect(coordinator.phase == .authenticated)
        #expect(try storage.load() == "fresh-token")
        #expect(await session.currentToken() == "fresh-token")
    }

    @Test func failedGateStaysAtTheGateWithAMessage() async {
        let biometrics = FakeBiometrics(shouldSucceed: false)
        let (coordinator, _, _) = makeCoordinator(
            storage: InMemoryTokenStorage(token: "persisted"),
            biometrics: biometrics
        )
        await coordinator.bootstrap()

        await coordinator.runBiometricGate()

        #expect(coordinator.phase == .biometricRequired)
        #expect(coordinator.biometricFailureMessage != nil)

        // Retry succeeds.
        biometrics.setShouldSucceed(true)
        await coordinator.runBiometricGate()
        #expect(coordinator.phase == .authenticated)
        #expect(coordinator.biometricFailureMessage == nil)
    }

    @Test func logoutClearsSessionAndReturnsToLogin() async throws {
        let (coordinator, session, storage) = makeCoordinator(storage: InMemoryTokenStorage(token: "persisted"))
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()
        #expect(coordinator.phase == .authenticated)

        await coordinator.logout()

        #expect(coordinator.phase == .loggedOut)
        #expect(try storage.load() == nil)
        #expect(await session.currentToken() == nil)
    }

    @Test func sessionExpiryClearsTheStoredToken() async throws {
        let (coordinator, _, storage) = makeCoordinator(storage: InMemoryTokenStorage(token: "stale"))
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()

        await coordinator.sessionExpired()

        #expect(coordinator.phase == .loggedOut)
        #expect(try storage.load() == nil)
    }
}
