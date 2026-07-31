import Foundation

/// The cache's disk tier, as a seam.
///
/// ARCH: extracted from CacheStore so the two-tier behavior ("memory hit
/// never touches disk") is provable with a spy instead of asserted with
/// hope. Production is a folder of files; tests count calls.
public protocol CacheDisk: Sendable {
    func read(key: String) -> Data?
    func write(key: String, data: Data)
    func delete(key: String)
    func deleteAll()
}

/// File-per-key storage under Application Support.
public struct FileCacheDisk: CacheDisk {
    private let directory: URL

    public init(directoryName: String) {
        // WHY Application Support and not Caches: the OS may purge Caches
        // under disk pressure, which would silently delete the offline
        // experience exactly when a user in a low-storage, low-connectivity
        // market needs it. This data is small and its lifecycle (logout
        // sweep) is ours.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func read(key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    public func write(key: String, data: Data) {
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

    public func delete(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    public func deleteAll() {
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
