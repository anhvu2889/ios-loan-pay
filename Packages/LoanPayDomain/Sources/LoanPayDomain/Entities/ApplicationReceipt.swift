import Foundation

/// Proof the backend accepted an application for review.
public struct ApplicationReceipt: Hashable, Sendable {
    public let applicationID: String
    public let submittedAt: Date

    public init(applicationID: String, submittedAt: Date) {
        self.applicationID = applicationID
        self.submittedAt = submittedAt
    }
}
