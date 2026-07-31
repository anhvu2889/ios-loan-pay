import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

/// Disk tier spy: a dictionary that counts every touch.
final class SpyCacheDisk: CacheDisk, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]
    private(set) var readCount = 0
    private(set) var writeCount = 0

    init(storage: [String: Data] = [:]) {
        self.storage = storage
    }

    var keys: Set<String> {
        lock.withLock { Set(storage.keys) }
    }

    func read(key: String) -> Data? {
        lock.withLock {
            readCount += 1
            return storage[key]
        }
    }

    func write(key: String, data: Data) {
        lock.withLock {
            writeCount += 1
            storage[key] = data
        }
    }

    func delete(key: String) {
        lock.withLock { storage[key] = nil }
    }

    func deleteAll() {
        lock.withLock { storage.removeAll() }
    }

    func snapshotStorage() -> [String: Data] {
        lock.withLock { storage }
    }
}

@Suite struct TwoTierCacheTests {
    private let page = LoanPage(index: 1, loans: [], hasMore: false)

    @Test func memoryHitNeverTouchesDisk() async {
        let disk = SpyCacheDisk()
        let store = CacheStore(disk: disk)

        await store.store(page, forKey: "k")
        _ = await store.load(LoanPage.self, forKey: "k")
        _ = await store.load(LoanPage.self, forKey: "k")

        // One write; ZERO reads — both loads were memory hits.
        #expect(disk.writeCount == 1)
        #expect(disk.readCount == 0)
    }

    @Test func coldStartReadsDiskOnceThenServesFromMemory() async {
        let seedDisk = SpyCacheDisk()
        await CacheStore(disk: seedDisk).store(page, forKey: "k")

        // A NEW store over the same disk contents = process relaunch:
        // memory is empty, disk is the cold-start source.
        let disk = SpyCacheDisk(storage: seedDisk.snapshotStorage())
        let store = CacheStore(disk: disk)

        let first = await store.load(LoanPage.self, forKey: "k")
        let second = await store.load(LoanPage.self, forKey: "k")

        #expect(first?.value == page)
        #expect(second?.value == page)
        // Disk was the cold-start source exactly once; the hit primed
        // memory and the second read skipped the disk.
        #expect(disk.readCount == 1)
    }

    @Test func removeAllClearsBothTiers() async {
        let disk = SpyCacheDisk()
        let store = CacheStore(disk: disk)
        await store.store(page, forKey: "k")

        await store.removeAll()

        #expect(await store.load(LoanPage.self, forKey: "k") == nil)
        #expect(disk.keys.isEmpty)
        // The nil load above was allowed to consult the (empty) disk —
        // what matters is nothing was there.
    }
}
