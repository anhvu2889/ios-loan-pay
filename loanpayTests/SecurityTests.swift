import Foundation
import Testing
import LoanPayDomain
import LoanPayData
import LoanPayFeatureKit
@testable import loanpay

// MARK: - Logout sweep

@MainActor
@Suite struct LogoutSweepTests {
    @Test func clearAllWipesTokenCacheAndOutboxEndToEnd() async throws {
        // Real stores over throwaway directories — the sweep is proven
        // against the same types production uses, only the Keychain is
        // substituted.
        let storage = InMemoryTokenStorage(token: "session-token")
        let session = SessionStore(storage: storage)
        let cache = CacheStore(directoryName: "SweepTests-cache-\(UUID().uuidString)")
        let outbox = OutboxStore(directoryName: "SweepTests-outbox-\(UUID().uuidString)")
        await session.registerWipeHandler { await cache.removeAll() }
        await session.registerWipeHandler { await outbox.removeAll() }

        _ = await session.bootstrap()
        await cache.store(LoanPage(index: 1, loans: [], hasMore: false), forKey: "loans-page-1")
        try await outbox.enqueue(.supportCallback(topic: "billing", loanID: nil))

        await session.clearAll()

        #expect(await session.currentToken() == nil)
        #expect(try storage.load() == nil)
        #expect(await cache.load(LoanPage.self, forKey: "loans-page-1") == nil)
        #expect(await outbox.currentStats().isEmpty)
    }

    @Test func logoutAndExpiryBothRunTheSweep() async throws {
        let cache = CacheStore(directoryName: "SweepTests-cache-\(UUID().uuidString)")
        let session = SessionStore(storage: InMemoryTokenStorage(token: "t"))
        await session.registerWipeHandler { await cache.removeAll() }
        let coordinator = AuthFlowCoordinator(
            session: session,
            biometrics: FakeBiometrics(shouldSucceed: true),
            logger: SilentLogger()
        )
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()
        await cache.store(LoanPage(index: 1, loans: [], hasMore: false), forKey: "k")

        await coordinator.sessionExpired()

        #expect(await cache.load(LoanPage.self, forKey: "k") == nil)
        #expect(coordinator.phase == .loggedOut)
    }
}

// MARK: - Inactivity timeout

@MainActor
@Suite struct InactivityTimeoutTests {
    private func makeAuthenticatedCoordinator(
        timeout: TimeInterval = 300
    ) async -> (AuthFlowCoordinator, InMemoryTokenStorage) {
        let storage = InMemoryTokenStorage(token: "t")
        let coordinator = AuthFlowCoordinator(
            session: SessionStore(storage: storage),
            biometrics: FakeBiometrics(shouldSucceed: true),
            logger: SilentLogger(),
            inactivityTimeout: timeout
        )
        await coordinator.bootstrap()
        await coordinator.runBiometricGate()
        return (coordinator, storage)
    }

    @Test func shortBackgroundHopCostsNothing() async throws {
        let (coordinator, storage) = await makeAuthenticatedCoordinator()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        coordinator.sceneDidEnterBackground(at: base)
        await coordinator.sceneDidBecomeActive(at: base.addingTimeInterval(60))

        #expect(coordinator.phase == .authenticated)
        #expect(try storage.load() == "t")
    }

    @Test func timeoutExpiresTheSessionThroughTheFullSweepPath() async throws {
        let (coordinator, storage) = await makeAuthenticatedCoordinator()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        coordinator.sceneDidEnterBackground(at: base)
        await coordinator.sceneDidBecomeActive(at: base.addingTimeInterval(301))

        // Cleared, not just re-gated: token gone, back through login +
        // biometric like any expired session.
        #expect(coordinator.phase == .loggedOut)
        #expect(try storage.load() == nil)
    }

    @Test func backgroundingWhileLoggedOutIsInert() async {
        let coordinator = AuthFlowCoordinator(
            session: SessionStore(storage: InMemoryTokenStorage()),
            biometrics: FakeBiometrics(shouldSucceed: true),
            logger: SilentLogger()
        )
        await coordinator.bootstrap()

        coordinator.sceneDidEnterBackground(at: .distantPast)
        await coordinator.sceneDidBecomeActive(at: .distantFuture)

        #expect(coordinator.phase == .loggedOut)
    }
}

// MARK: - Deep-link fuzz matrix

@MainActor
@Suite struct DeepLinkFuzzTests {
    private func makeDispatcher() -> DeepLinkDispatcher {
        let dispatcher = DeepLinkDispatcher(logger: SilentLogger())
        FeatureRegistration.registerAll(dispatcher: dispatcher)
        return dispatcher
    }

    @Test(arguments: [
        // Oversized: a 65+ char id must die at the length cap.
        "loanpay://loans/\(String(repeating: "a", count: 65))",
        "loanpay://payment/\(String(repeating: "9", count: 500))/methods",
        // Illegal characters and injection shapes.
        "loanpay://loans/loan%20001",
        "loanpay://loans/loan';drop--",
        "loanpay://payment/%3Cscript%3E/methods",
        "loanpay://support/callback/topic%00null",
        // Traversal shapes.
        "loanpay://loans/..%2F..%2Fetc%2Fpasswd",
        "loanpay://payment/..%5C..%5Cwindows/methods",
        // Structure abuse.
        "loanpay://loans/a/b/c/d/e",
        "loanpay://payment//methods",
        "loanpay://support/callback/a/b/c",
    ])
    func hostileLinksAreDroppedNotDispatched(raw: String) {
        guard let url = URL(string: raw) else {
            return // unparseable URLs never even reach the dispatcher
        }
        #expect(makeDispatcher().dispatch(url, isAuthenticated: true) == nil)
    }

    @Test func maximumLegalIdentifierStillPasses() {
        // Boundary check: exactly 64 chars is legal — the cap is 65.
        let id = String(repeating: "a", count: 64)
        let outcome = makeDispatcher().dispatch(
            URL(string: "loanpay://loans/\(id)")!,
            isAuthenticated: true
        )
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.loanDetail(LoanID(id))]
        )))
    }
}
