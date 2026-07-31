import Foundation

public struct Installment: Hashable, Sendable, Identifiable, Codable {
    // LANG: `Status` is nested rather than a top-level `InstallmentStatus`
    // because it is meaningless outside an installment; nesting keeps the
    // namespace honest (`Installment.Status.paid` reads as the domain talks).
    public enum Status: String, Sendable, Hashable, Codable {
        case paid
        case due
        case overdue
        case upcoming
    }

    /// 1-based position in the repayment schedule.
    public let number: Int
    public let dueDate: Date
    public let amount: Money
    public let status: Status

    public var id: Int { number }

    public init(number: Int, dueDate: Date, amount: Money, status: Status) {
        self.number = number
        self.dueDate = dueDate
        self.amount = amount
        self.status = status
    }
}
