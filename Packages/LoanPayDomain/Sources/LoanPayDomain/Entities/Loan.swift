import Foundation

public typealias LoanID = Identifier<Loan>

/// The list-level summary of a financed device loan. The full installment
/// book lives on ``LoanDetail`` — list screens page through hundreds of
/// these, so this type carries only what a row and the portfolio header need.
public struct Loan: Identifiable, Hashable, Sendable, Codable {
    public let id: LoanID
    /// The financed handset, e.g. "Galaxy A15". The device is the collateral.
    public let deviceModel: String
    public let deviceImageURL: URL?
    public let principal: Money
    public let outstandingBalance: Money
    public let monthlyInstallment: Money
    public let status: LoanStatus
    public let nextInstallmentDue: Date?

    public init(
        id: LoanID,
        deviceModel: String,
        deviceImageURL: URL?,
        principal: Money,
        outstandingBalance: Money,
        monthlyInstallment: Money,
        status: LoanStatus,
        nextInstallmentDue: Date?
    ) {
        self.id = id
        self.deviceModel = deviceModel
        self.deviceImageURL = deviceImageURL
        self.principal = principal
        self.outstandingBalance = outstandingBalance
        self.monthlyInstallment = monthlyInstallment
        self.status = status
        self.nextInstallmentDue = nextInstallmentDue
    }
}
