import Foundation
import LoanPayDomain

/// Mock delivery: the support-callback endpoint, latency and failures via
/// the shared behavior actor (so the debug menu can break the outbox too).
public struct MockOutboxDelivery: OutboxDelivering {
    private let behavior: MockBehavior
    private let sleeper: any Sleeper

    public init(behavior: MockBehavior, sleeper: any Sleeper = ContinuousSleeper()) {
        self.behavior = behavior
        self.sleeper = sleeper
    }

    public func deliver(_ operation: OutboxOperation) async throws {
        try await ErrorMapper.mapping {
            _ = try await behavior.preflight(.supportCallback, sleeper: sleeper)
        }
    }
}
