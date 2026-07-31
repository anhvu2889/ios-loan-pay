import Foundation

public protocol LoanApplicationRepository: Sendable {
    /// The devices currently offered for financing.
    func fetchDeviceCatalog() async throws -> [String]

    func submit(_ application: LoanApplication) async throws -> ApplicationReceipt
}
