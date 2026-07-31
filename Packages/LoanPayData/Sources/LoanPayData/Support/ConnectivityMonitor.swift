import Foundation
import Network
import LoanPayDomain

/// `ConnectivityMonitoring` over NWPathMonitor.
///
/// ARCH: the dedupe logic is separated from the NWPathMonitor plumbing so
/// the interesting part (transitions, not chatter) is unit-testable with a
/// scripted stream — Network.framework cannot be faked, but it doesn't
/// need to be.
public struct ConnectivityMonitor: ConnectivityMonitoring {
    private let rawUpdates: @Sendable () -> AsyncStream<Bool>

    /// Production: wraps a fresh NWPathMonitor per subscription.
    public init() {
        self.rawUpdates = {
            AsyncStream { continuation in
                // MODERN: NWPathMonitor (iOS 12) replaced SCNetworkReachability,
                // which was callback-C API, famously racy at launch, and
                // easy to leak. Bridged here into AsyncStream so consumers
                // just `for await` — no delegate, no queue juggling.
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { path in
                    continuation.yield(path.status == .satisfied)
                }
                monitor.start(queue: DispatchQueue(label: "connectivity-monitor"))
                continuation.onTermination = { _ in
                    monitor.cancel()
                }
            }
        }
    }

    /// Testable: any source of raw online/offline booleans.
    public init(rawUpdates: @escaping @Sendable () -> AsyncStream<Bool>) {
        self.rawUpdates = rawUpdates
    }

    public func statusUpdates() -> AsyncStream<ConnectivityStatus> {
        let source = rawUpdates
        return AsyncStream { continuation in
            let task = Task {
                var lastStatus: ConnectivityStatus?
                for await isOnline in source() {
                    let status: ConnectivityStatus = isOnline ? .online : .offline
                    // The dedupe promise from the protocol: consumers see
                    // transitions only.
                    guard status != lastStatus else { continue }
                    lastStatus = status
                    continuation.yield(status)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
