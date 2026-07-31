import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct CacheStoreTests {
    private func makeStore(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> CacheStore {
        // Unique directory per test — suites run in parallel and must not
        // share files.
        CacheStore(directoryName: "CacheStoreTests-\(UUID().uuidString)", now: { now })
    }

    @Test func roundTripsValuesWithTheirFetchTime() async {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: stamp)
        let page = LoanPage(index: 1, loans: [], hasMore: false)

        await store.store(page, forKey: "loans-page-1")
        let hit = await store.load(LoanPage.self, forKey: "loans-page-1")

        #expect(hit?.value == page)
        #expect(hit?.fetchedAt == stamp)
    }

    @Test func missReturnsNil() async {
        let store = makeStore()
        #expect(await store.load(LoanPage.self, forKey: "nothing-here") == nil)
    }

    @Test func removeAllSweepsEveryEntry() async {
        let store = makeStore()
        await store.store(LoanPage(index: 1, loans: [], hasMore: false), forKey: "a")
        await store.store(LoanPage(index: 2, loans: [], hasMore: false), forKey: "b")

        await store.removeAll()

        #expect(await store.load(LoanPage.self, forKey: "a") == nil)
        #expect(await store.load(LoanPage.self, forKey: "b") == nil)
    }

    @Test func typeMismatchReadsAsAMissNotACrash() async {
        let store = makeStore()
        await store.store(LoanPage(index: 1, loans: [], hasMore: false), forKey: "k")
        // Old schema on disk, new type requested → miss, silently.
        #expect(await store.load([String].self, forKey: "k") == nil)
    }
}
