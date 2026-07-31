import Foundation

// ARCH: the seam that keeps the Keychain OUT of tests. SessionStore's logic
// (caching, clearing, bootstrap) is worth testing; Security.framework calls
// inside a test runner are worth avoiding — they prompt, they depend on
// entitlements, and they leak state between runs. Production injects the
// Keychain implementation; tests inject a dictionary.
public protocol TokenStorage: Sendable {
    func save(_ token: String) throws
    func load() throws -> String?
    func delete() throws
}
