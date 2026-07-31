import Foundation
import Testing
import LoanPayDomain

@Suite struct DomainErrorTests {
    @Test(arguments: [
        DomainError.offline,
        .timeout,
        .serverError(code: 503),
        .unknown,
    ])
    func transientErrorsAreRetryable(error: DomainError) {
        #expect(error.isRetryable)
    }

    @Test(arguments: [
        DomainError.unauthorized,
        .notFound,
        .invalidData(keyPath: "loan.balance"),
    ])
    func deterministicFailuresAreNotRetryable(error: DomainError) {
        #expect(!error.isRetryable)
    }

    @Test func userMessagesCarryNoTransportJargon() {
        let allCases: [DomainError] = [
            .offline, .timeout, .unauthorized, .notFound,
            .serverError(code: 500), .invalidData(keyPath: "x"), .unknown,
        ]
        for error in allCases {
            #expect(!error.userMessage.isEmpty)
            // A borrower should never see status codes or type names.
            #expect(!error.userMessage.contains("500"))
            #expect(!error.userMessage.lowercased().contains("http"))
            #expect(!error.userMessage.contains("URL"))
        }
    }
}
