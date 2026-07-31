import Foundation

/// A submitted application for financing a new device.
public struct LoanApplication: Hashable, Sendable {
    public let applicantName: String
    public let monthlyIncome: Money
    public let deviceModel: String
    public let preferredStartDate: Date
    /// When the applicant accepted the terms — recorded, not just a Bool,
    /// because "did they agree and when" is an auditable fact.
    public let termsAcceptedAt: Date

    public init(
        applicantName: String,
        monthlyIncome: Money,
        deviceModel: String,
        preferredStartDate: Date,
        termsAcceptedAt: Date
    ) {
        self.applicantName = applicantName
        self.monthlyIncome = monthlyIncome
        self.deviceModel = deviceModel
        self.preferredStartDate = preferredStartDate
        self.termsAcceptedAt = termsAcceptedAt
    }
}
