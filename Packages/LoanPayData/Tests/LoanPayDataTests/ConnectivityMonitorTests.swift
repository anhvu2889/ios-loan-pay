import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct ConnectivityMonitorTests {
    @Test func consecutiveDuplicateStatesAreFiltered() async {
        let monitor = ConnectivityMonitor(rawUpdates: {
            AsyncStream { continuation in
                // NWPathMonitor-style chatter: repeated same-state updates.
                for isOnline in [true, true, false, false, false, true] {
                    continuation.yield(isOnline)
                }
                continuation.finish()
            }
        })

        var seen: [ConnectivityStatus] = []
        for await status in monitor.statusUpdates() {
            seen.append(status)
        }

        // Transitions only: the banner toggles three times, not six.
        #expect(seen == [.online, .offline, .online])
    }
}
