import Foundation
import LoanPayDomain

/// File-backed JSON cache: one file per key, each carrying its value and
/// the time it was fetched.
///
/// LANG: an actor because reads and writes arrive from arbitrary tasks
/// (list refresh, detail prefetch, logout sweep) and file I/O + the
/// in-flight dictionary of writes must not interleave. Actor isolation is
/// the cheapest correct tool here — a queue would serialize the same way
/// with more ceremony.
public actor CacheStore {
    private let directory: URL
    private let now: @Sendable () -> Date

    private struct Entry<Value: Codable>: Codable {
        let value: Value
        let fetchedAt: Date
    }

    public init(
        directoryName: String = "LoanPayCache",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        // WHY Application Support and not Caches: the OS may purge Caches
        // under disk pressure, which would silently delete the offline
        // experience exactly when a user in a low-storage, low-connectivity
        // market needs it. This data is small and we manage its lifecycle
        // (logout sweep) ourselves.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func store<Value: Codable & Sendable>(_ value: Value, forKey key: String) {
        let entry = Entry(value: value, fetchedAt: now())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        // FINTECH: cached loans are PII — balances, device collateral,
        // schedules. `.completeFileProtection` keeps the files encrypted
        // whenever the device is locked; a cache readable from a locked,
        // stolen phone would undo everything the Keychain protects.
        #if os(iOS)
        try? data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: fileURL(for: key), options: [.atomic])
        #endif
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) -> (value: Value, fetchedAt: Date)? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data) else {
            // WHY corrupt == absent: a cache must never fail a read. An
            // undecodable file (schema drift between app versions, torn
            // write) is treated as a miss and quietly replaced on the next
            // store.
            return nil
        }
        return (entry.value, entry.fetchedAt)
    }

    public func remove(forKey key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// The logout sweep: cached loan data is PII and leaves WITH the user.
    public func removeAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(for key: String) -> URL {
        // Keys are internal constants, but sanitizing them keeps a future
        // dynamic key (a loan id) from ever writing outside the directory.
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }
}
