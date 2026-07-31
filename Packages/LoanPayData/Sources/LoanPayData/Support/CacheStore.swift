import Foundation
import LoanPayDomain

/// Two-tier cache: an in-memory map in front of a file-backed disk tier.
///
/// Read path: memory hit → disk hit (primes memory) → miss. Write path:
/// both tiers. The disk remains the COLD-START source — memory exists only
/// to spare repeat reads the file I/O and JSON decode on hot paths (every
/// list appearance reads the cache).
///
/// LANG: an actor because reads and writes arrive from arbitrary tasks
/// (list refresh, detail prefetch, logout sweep) and the two tiers must
/// change together. Actor isolation is the cheapest correct tool — a queue
/// would serialize the same way with more ceremony.
public actor CacheStore {
    private let disk: any CacheDisk
    private let now: @Sendable () -> Date
    /// Memory tier: key → the same encoded entry the disk holds. Storing
    /// encoded bytes (not decoded values) keeps the two tiers trivially
    /// coherent — one representation, two locations.
    private var memory: [String: Data] = [:]

    private struct Entry<Value: Codable>: Codable {
        let value: Value
        let fetchedAt: Date
    }

    public init(
        disk: any CacheDisk,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.disk = disk
        self.now = now
    }

    /// Convenience: file-backed disk tier under the given directory.
    public init(
        directoryName: String = "LoanPayCache",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(disk: FileCacheDisk(directoryName: directoryName), now: now)
    }

    public func store<Value: Codable & Sendable>(_ value: Value, forKey key: String) {
        let entry = Entry(value: value, fetchedAt: now())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        memory[key] = data
        disk.write(key: key, data: data)
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: String
    ) -> (value: Value, fetchedAt: Date)? {
        // Tier 1: memory. A hit never touches the file system.
        if let data = memory[key], let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data) {
            return (entry.value, entry.fetchedAt)
        }
        // Tier 2: disk (cold start). A hit primes memory for next time.
        guard let data = disk.read(key: key),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data) else {
            // WHY corrupt == absent: a cache must never fail a read. An
            // undecodable file (schema drift between app versions, torn
            // write) is treated as a miss and quietly replaced on the next
            // store.
            return nil
        }
        memory[key] = data
        return (entry.value, entry.fetchedAt)
    }

    public func remove(forKey key: String) {
        memory[key] = nil
        disk.delete(key: key)
    }

    /// The logout sweep: cached loan data is PII and leaves WITH the user —
    /// from BOTH tiers.
    public func removeAll() {
        memory.removeAll()
        disk.deleteAll()
    }
}
