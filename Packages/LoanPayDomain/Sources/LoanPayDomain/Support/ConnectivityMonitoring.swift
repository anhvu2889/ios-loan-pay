import Foundation

public enum ConnectivityStatus: Equatable, Sendable {
    case online
    case offline
}

/// Push-based connectivity: consumers `for await` status changes.
///
/// The stream contract: consecutive duplicate states are filtered — a
/// consumer sees TRANSITIONS, not chatter. (NWPathMonitor fires on every
/// path re-evaluation; without dedupe an "offline banner" would flicker on
/// each cell-tower handoff.)
public protocol ConnectivityMonitoring: Sendable {
    func statusUpdates() -> AsyncStream<ConnectivityStatus>
}
