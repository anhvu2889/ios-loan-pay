import Foundation
import LoanPayDomain

public struct MockLoanApplicationRepository: LoanApplicationRepository {
    private let behavior: MockBehavior
    private let sleeper: any Sleeper

    public init(behavior: MockBehavior, sleeper: any Sleeper = ContinuousSleeper()) {
        self.behavior = behavior
        self.sleeper = sleeper
    }

    public func fetchDeviceCatalog() async throws -> [String] {
        // The catalog is static in the mock; the real one is a merch-
        // managed endpoint. No preflight — a broken catalog fetch should
        // not be a testable failure mode anyone depends on.
        [
            "Galaxy A15", "Galaxy A25", "Redmi 13C", "Redmi Note 13",
            "Tecno Spark 20", "Infinix Hot 40i", "itel A70", "Nokia G22",
            "Oppo A18", "Vivo Y17s",
        ]
    }

    public func submit(_ application: LoanApplication) async throws -> ApplicationReceipt {
        try await ErrorMapper.mapping {
            _ = try await behavior.preflight(.submitApplication, sleeper: sleeper)
            return ApplicationReceipt(
                applicationID: "app-\(UUID().uuidString.prefix(8))",
                submittedAt: Date()
            )
        }
    }
}
