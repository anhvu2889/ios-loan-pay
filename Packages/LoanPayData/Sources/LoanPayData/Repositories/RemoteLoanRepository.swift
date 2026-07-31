import Foundation
import LoanPayDomain

/// `LoanRepository` over the reference HTTP client, shaped for the local
/// json-server in `Scripts/mock-server`.
public struct RemoteLoanRepository: LoanRepository {
    private let client: URLSessionAPIClient
    private let pageSize = 8

    public init(client: URLSessionAPIClient) {
        self.client = client
    }

    public func fetchLoans(page: Int) async throws -> LoanPage {
        try await ErrorMapper.mapping {
            // WHY fetch-all-and-slice: json-server is a dumb static server
            // and this path exists to exercise REAL networking, not to
            // fake a paging backend. The repository seam hides the
            // difference — a production backend pages server-side and only
            // this file changes.
            let all: [LoanDTO] = try await client.get("loans")
            let start = (page - 1) * pageSize
            guard start >= 0, start < all.count else {
                return LoanPage(index: page, loans: [], hasMore: false)
            }
            let end = min(start + pageSize, all.count)
            return LoanPage(
                index: page,
                loans: try all[start..<end].map { try $0.toDomain() },
                hasMore: end < all.count
            )
        }
    }

    public func fetchLoanDetail(id: LoanID) async throws -> LoanDetail {
        try await ErrorMapper.mapping {
            let dto: LoanDTO = try await client.get("loans/\(id.rawValue)")
            // The static server has no detail endpoint; the repayment book
            // is derived the same way the in-process mock derives it.
            return MockLoanDetailSynthesizer.detail(for: try dto.toDomain())
        }
    }

    public func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        try await ErrorMapper.mapping {
            let dto: LoanDTO = try await client.get("loans/\(id.rawValue)")
            let loan = try dto.toDomain()
            return PayoffQuote(loanID: loan.id, amount: loan.outstandingBalance, asOf: Date())
        }
    }

    public func searchLoans(matching query: String) async throws -> [Loan] {
        try await ErrorMapper.mapping {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let results: [LoanDTO] = try await client.get(
                "loans",
                query: [URLQueryItem(name: "q", value: trimmed)]
            )
            // Belt-and-suspenders: json-server's q= is full-text over every
            // field; re-filter so a balance digit match can't surface an
            // unrelated loan.
            return try results.map { try $0.toDomain() }
                .filter { $0.deviceModel.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}
