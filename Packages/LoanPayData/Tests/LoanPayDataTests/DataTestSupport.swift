import Foundation
import LoanPayDomain
@testable import LoanPayData

/// Records requested delays and returns immediately — the mock's simulated
/// latency becomes an assertable value, and the suite never sleeps.
actor RecordingSleeper: Sleeper {
    private(set) var recordedDelays: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDelays.append(duration)
    }
}

/// A behavior with zero base latency — repository tests opt into failure
/// modes explicitly and never pay simulated network time.
func makeInstantBehavior() -> MockBehavior {
    MockBehavior(latency: .zero)
}

func makeLoanRepository(
    behavior: MockBehavior,
    sleeper: RecordingSleeper = RecordingSleeper()
) -> MockLoanRepository {
    MockLoanRepository(behavior: behavior, sleeper: sleeper)
}
