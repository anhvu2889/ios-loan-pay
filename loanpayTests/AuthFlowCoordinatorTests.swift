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
    /// The assembled system under test plus the two seams asserts reach.
    private struct Harness {
        let coordinator: AuthFlowCoordinator
        let session: SessionStore
        let storage: InMemoryTokenStorage
    }

    private func makeHarness(
        storage: InMemoryTokenStorage = InMemoryTokenStorage(),
        biometrics: FakeBiometrics = FakeBiometrics(shouldSucceed: true)
    ) -> Harness {
        let session = SessionStore(storage: storage)
        let coordinator = AuthFlowCoordinator(
            session: session,
            biometrics: biometrics,
            logger: SilentLogger()
        )
        return Harness(coordinator: coordinator, session: session, storage: storage)
    }

    @Test func bootstrapWithoutSessionLandsOnLogin() async {
        let coordinator = makeHarness().coordinator
        await coordinator.bootstrap()
        #expect(coordinator.phase == .loggedOut)
    }

    @Test func bootstrapWithPersistedSessionStillRequiresTheGate() async {
        let coordinator = makeHarness(storage: InMemoryTokenStorage(token: "persisted")).coordinator
        await coordinator.bootstrap()
        // A stored token is NOT enough to see balances — presence first.
        #expect(coordinator.phase == .biometricRequired)
    }

    @Test func freshLoginStoresTheTokenOnlyAfterTheGatePasses() async throws {
        let harness = makeHarness()
        let (coordinator, session, storage) = (harness.coordinator, harness.session, harness.storage)
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
        let coordinator = makeHarness(
            storage: InMemoryTokenStorage(token: "persisted"),
            biometrics: biometrics
        ).coordinator
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
        let harness = makeHarness(storage: InMemoryTokenStorage(token: "persisted"))
        let (coordinator, session, storage) = (harness.coordinator, harness.session, harness.storage)
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()
        #expect(coordinator.phase == .authenticated)

        await coordinator.logout()

        #expect(coordinator.phase == .loggedOut)
        #expect(try storage.load() == nil)
        #expect(await session.currentToken() == nil)
    }

    @Test func sessionExpiryClearsTheStoredToken() async throws {
        let harness = makeHarness(storage: InMemoryTokenStorage(token: "stale"))
        let (coordinator, storage) = (harness.coordinator, harness.storage)
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()

        await coordinator.sessionExpired()

        #expect(coordinator.phase == .loggedOut)
        #expect(try storage.load() == nil)
    }
}
