import Foundation

public enum LoanStatus: String, Sendable, Hashable, CaseIterable, Codable {
    case active
    case overdue
    case paidOff

    // FINTECH: fail-open display. When the server introduces a status this
    // build has never heard of, the loan must still appear in the list — a
    // borrower whose loan silently vanishes from their phone will assume the
    // debt vanished too. The mapper funnels unrecognized wire values here
    // instead of throwing the whole payload away.
    case unknown
}
