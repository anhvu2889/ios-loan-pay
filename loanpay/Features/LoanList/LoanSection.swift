import Foundation
import LoanPayDomain

/// One status-grouped slice of the loan list.
struct LoanSection: Identifiable, Equatable {
    let status: LoanStatus
    let loans: [Loan]

    var id: LoanStatus { status }

    /// Section order is a business statement: what needs attention comes
    /// first, history comes last.
    static let displayOrder: [LoanStatus] = [.overdue, .active, .unknown, .paidOff]

    static func grouping(_ loans: [Loan]) -> [LoanSection] {
        let grouped = Dictionary(grouping: loans, by: \.status)
        return displayOrder.compactMap { status in
            guard let loans = grouped[status], !loans.isEmpty else { return nil }
            return LoanSection(status: status, loans: loans)
        }
    }
}
