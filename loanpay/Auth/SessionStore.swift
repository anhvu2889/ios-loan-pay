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
}
