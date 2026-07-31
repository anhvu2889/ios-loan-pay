import Foundation
import Observation
import LoanPayDomain
import LoanPayData

/// Feeds the sync badge: pending/failed counts pushed by the store.
@Observable
@MainActor
final class OutboxStatusViewModel {
    private(set) var pendingCount = 0
    private(set) var hasFailures = false

    @ObservationIgnored private(set) var watchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?

    private let store: OutboxStore
    private let drainer: OutboxDrainer

    init(store: OutboxStore, drainer: OutboxDrainer) {
        self.store = store
        self.drainer = drainer
    }

    func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self, store] in
            for await stats in await store.statsUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.pendingCount = stats.pendingCount + stats.failedCount
                self.hasFailures = stats.failedCount > 0
            }
        }
    }

    func retry() {
        retryTask = Task { [drainer] in
            await drainer.retryFailed()
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }
}
