import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

/// In-memory TokenStorage — the Keychain NEVER runs in tests.
///
/// LANG: `final class` + NSLock rather than an actor because TokenStorage's
/// methods are synchronous (the production Keychain calls are too); an
/// actor would force `await` into every conformance.
final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private(set) var saveCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func save(_ token: String) throws {
        lock.withLock {
            self.token = token
            saveCount += 1
        }
    }

    func load() throws -> String? {
        lock.withLock { token }
    }

    func delete() throws {
        lock.withLock { token = nil }
    }
}

@Suite struct SessionStoreTests {
    @Test func bootstrapFindsAPersistedSession() async throws {
        let store = SessionStore(storage: InMemoryTokenStorage(token: "persisted-token"))

        #expect(await store.bootstrap())
        #expect(await store.currentToken() == "persisted-token")
    }

    @Test func bootstrapWithNoTokenReportsNoSession() async {
        let store = SessionStore(storage: InMemoryTokenStorage())
        #expect(await !store.bootstrap())
        #expect(await store.currentToken() == nil)
    }

    @Test func storeWritesThroughToDurableStorage() async throws {
        let storage = InMemoryTokenStorage()
        let store = SessionStore(storage: storage)

        try await store.store(token: "fresh-token")

        #expect(await store.currentToken() == "fresh-token")
        #expect(try storage.load() == "fresh-token")
    }

    @Test func clearRemovesMemoryAndDurableCopies() async throws {
        let storage = InMemoryTokenStorage(token: "old")
        let store = SessionStore(storage: storage)
        _ = await store.bootstrap()

        try await store.clear()

        #expect(await store.currentToken() == nil)
        #expect(try storage.load() == nil)
    }
}
