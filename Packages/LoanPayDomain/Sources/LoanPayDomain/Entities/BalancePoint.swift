import Foundation

/// One sample of the outstanding balance over the life of a loan; the detail
/// screen's balance chart is a series of these.
public struct BalancePoint: Hashable, Sendable, Codable {
    public let date: Date
    public let balance: Money

    public init(date: Date, balance: Money) {
        self.date = date
        self.balance = balance
    }
}
