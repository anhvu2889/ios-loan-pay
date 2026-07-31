import Foundation
import LoanPayDomain

struct LoanPageDTO: Decodable {
    let page: Int
    let loans: [LoanDTO]
    let hasMore: Bool

    func toDomain() throws -> LoanPage {
        LoanPage(index: page, loans: try loans.map { try $0.toDomain() }, hasMore: hasMore)
    }
}
