import Foundation
import Security
import LoanPayDomain

/// Minimal Keychain-backed `TokenStorage`: one generic-password item.
///
/// FINTECH: the session token NEVER touches UserDefaults — defaults are a
/// plaintext plist, readable in any unencrypted backup and by anything
/// with file access on a jailbroken device. The Keychain entry is created
/// `WhenUnlockedThisDeviceOnly`: unavailable before first unlock (a stolen
/// powered-off phone yields nothing) and excluded from iCloud/backup
/// restore (`ThisDeviceOnly` — a session must not silently migrate to a
/// new device with different trust).
struct KeychainWrapper: TokenStorage {
    private let service: String

    init(service: String = "com.anhvu.loanpay.session") {
        self.service = service
    }

    func save(_ token: String) throws {
        // WHY delete-then-add: SecItemUpdate has a separate code path and
        // error surface; for a single-item store, replace is simpler to
        // reason about and idempotent.
        try? delete()
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "session-token",
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "session-token",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "session-token",
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }
}
