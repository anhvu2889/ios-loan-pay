import Foundation
import LoanPayDomain

/// Holds the session token for the life of the process, backed by durable
/// storage.
///
/// LANG: an actor, not @MainActor — the token is read by REPOSITORIES
/// (attaching Authorization headers off the main thread) and written by the
/// auth flow (main thread). Actor isolation gives both sides safe access
/// without dragging network code onto the UI's actor.
actor SessionStore {
    private let storage: any TokenStorage
    private var cachedToken: String?
    private var didBootstrap = false

    init(storage: any TokenStorage) {
        self.storage = storage
    }

    /// Loads any persisted token once. Returns whether a session exists.
    func bootstrap() -> Bool {
        if !didBootstrap {
            // WHY swallow the error: a corrupt/unreadable Keychain item at
            // launch means "no session" and a fresh login — failing to boot
            // the app over it would turn a recoverable state into a brick.
            cachedToken = try? storage.load()
            didBootstrap = true
        }
        return cachedToken != nil
    }

    func store(token: String) throws {
        try storage.save(token)
        cachedToken = token
    }

    func currentToken() -> String? {
        cachedToken
    }

    /// Ends the session: memory and durable copy both go.
    func clear() throws {
        cachedToken = nil
        try storage.delete()
    }

    // MARK: - The logout sweep

    /// PII stores register here at composition time (cache, outbox).
    ///
    /// ARCH: the session store doesn't import the cache or outbox — it
    /// owns the SWEEP CONTRACT, the composition root supplies the brooms.
    /// One call site (`clearAll`) is what makes "logout wipes everything"
    /// an invariant instead of a checklist.
    func registerWipeHandler(_ handler: @escaping @Sendable () async -> Void) {
        wipeHandlers.append(handler)
    }

    /// The one logout/expiry sweep: token, then every registered PII store.
    ///
    /// FINTECH: cached loans, queued support requests and the session token
    /// are all borrower data. A logout that keeps any of them leaves the
    /// next person holding the phone a readable ledger.
    func clearAll() async {
        cachedToken = nil
        try? storage.delete()
        for handler in wipeHandlers {
            await handler()
        }
    }

    private var wipeHandlers: [@Sendable () async -> Void] = []
}
