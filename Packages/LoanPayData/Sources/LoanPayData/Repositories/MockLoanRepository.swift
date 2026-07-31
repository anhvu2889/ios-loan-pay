import Foundation
import LoanPayDomain

/// The in-process "backend": JSON-backed, latency-simulating, failure-
/// injectable. Implements the same `LoanRepository` contract as the real
/// URLSession implementation, so the entire app runs against it unchanged.
public struct MockLoanRepository: LoanRepository {
    private let behavior: MockBehavior
    private let sleeper: any Sleeper
    // WHY 8: with 25 fixture loans this yields four pages — enough to
    // exercise "several pages, then the end" in manual testing without
    // endless scrolling.
    private let pageSize: Int

    public init(
        behavior: MockBehavior,
        sleeper: any Sleeper = ContinuousSleeper(),
        pageSize: Int = 8
    ) {
        self.behavior = behavior
        self.sleeper = sleeper
        self.pageSize = pageSize
    }

    public func fetchLoans(page: Int) async throws -> LoanPage {
        try await ErrorMapper.mapping {
            let directive = try await behavior.preflight(.loanList, sleeper: sleeper)
            let all = try Self.decodeLoans(directive)
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
            let directive = try await behavior.preflight(.loanDetail, sleeper: sleeper)
            guard let dto = try Self.decodeLoans(directive).first(where: { $0.id == id.rawValue }) else {
                // WHY a transport error and not DomainError.notFound: the
                // real backend answers a missing id with HTTP 404; the mock
                // must walk the identical mapper path.
                throw HTTPError(statusCode: 404)
            }
            return MockLoanDetailSynthesizer.detail(for: try dto.toDomain())
        }
    }

    public func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote {
        try await ErrorMapper.mapping {
            let directive = try await behavior.preflight(.payoffQuote, sleeper: sleeper)
            guard let dto = try Self.decodeLoans(directive).first(where: { $0.id == id.rawValue }) else {
                throw HTTPError(statusCode: 404)
            }
            let loan = try dto.toDomain()
            return PayoffQuote(loanID: loan.id, amount: loan.outstandingBalance, asOf: Date())
        }
    }

    public func searchLoans(matching query: String) async throws -> [Loan] {
        try await ErrorMapper.mapping {
            let directive = try await behavior.preflight(.search, sleeper: sleeper)
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return try Self.decodeLoans(directive)
                .filter { $0.deviceModel.localizedCaseInsensitiveContains(trimmed) }
                .map { try $0.toDomain() }
        }
    }

    private static func decodeLoans(_ directive: MockBehavior.Directive) throws -> [LoanDTO] {
        let data: Data
        switch directive {
        case .proceed:
            data = try MockFixtures.data(named: "loans")
        case .serveMalformedPayload:
            data = MockFixtures.malformedData
        }
        return try MockFixtures.makeDecoder().decode([LoanDTO].self, from: data)
    }
}
