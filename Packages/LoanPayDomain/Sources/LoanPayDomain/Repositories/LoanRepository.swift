import Foundation

// ARCH: The seam between "what the app needs to know about loans" and
// "where that knowledge comes from". Mock, URLSession-backed and
// cache-decorated implementations all satisfy this same contract, which is
// why screens and use cases never change when the data source does.
//
// LANG: `Sendable` is part of the contract on purpose: repositories are
// handed across actor boundaries (MainActor ViewModels → background work),
// so thread-safety is a requirement of every conforming type, enforced at
// compile time rather than promised in a comment.
public protocol LoanRepository: Sendable {
    func fetchLoans(page: Int) async throws -> LoanPage
    func fetchLoanDetail(id: LoanID) async throws -> LoanDetail
    func fetchPayoffQuote(id: LoanID) async throws -> PayoffQuote
    func searchLoans(matching query: String) async throws -> [Loan]
}
