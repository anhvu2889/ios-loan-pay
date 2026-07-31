import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct ErrorMapperTests {
    @Test func offlineURLErrorsMapToOffline() {
        #expect(ErrorMapper.domainError(from: URLError(.notConnectedToInternet)) == .offline)
        #expect(ErrorMapper.domainError(from: URLError(.networkConnectionLost)) == .offline)
    }

    @Test func timeoutMapsToTimeout() {
        #expect(ErrorMapper.domainError(from: URLError(.timedOut)) == .timeout)
    }

    @Test func httpStatusesMapByClass() {
        #expect(ErrorMapper.domainError(from: HTTPError(statusCode: 401)) == .unauthorized)
        #expect(ErrorMapper.domainError(from: HTTPError(statusCode: 404)) == .notFound)
        #expect(ErrorMapper.domainError(from: HTTPError(statusCode: 500)) == .serverError(code: 500))
        #expect(ErrorMapper.domainError(from: HTTPError(statusCode: 503)) == .serverError(code: 503))
    }

    @Test func decodingErrorCarriesKeyPathOnly() throws {
        struct Probe: Decodable { let loan: Inner }
        struct Inner: Decodable { let balance: String }
        do {
            _ = try JSONDecoder().decode(Probe.self, from: Data(#"{"loan": {"balance": 42}}"#.utf8))
            Issue.record("decode should have failed")
        } catch {
            let mapped = ErrorMapper.domainError(from: error)
            #expect(mapped == .invalidData(keyPath: "loan.balance"))
        }
    }

    @Test func existingDomainErrorsPassThroughUnchanged() {
        #expect(ErrorMapper.domainError(from: DomainError.notFound) == .notFound)
    }

    @Test func cancellationIsNeverTranslated() async {
        // WHY: cancellation means "the caller left", not "something broke" —
        // it must surface as CancellationError so ViewModels can ignore it.
        await #expect(throws: CancellationError.self) {
            try await ErrorMapper.mapping { throw CancellationError() }
        }
    }
}
