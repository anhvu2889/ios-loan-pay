import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

/// Serialized: StubURLProtocol.handler is process-global.
@Suite(.serialized) struct URLSessionAPIClientTests {
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []

        var requests: [URLRequest] {
            lock.withLock { _requests }
        }

        func append(_ request: URLRequest) {
            lock.withLock { _requests.append(request) }
        }
    }

    private func makeClient(token: String? = "test-token") -> URLSessionAPIClient {
        URLSessionAPIClient(
            baseURL: URL(string: "https://api.test.loanpay")!,
            session: StubURLProtocol.makeSession(),
            tokenProvider: { token },
            logger: SilentDataLogger()
        )
    }

    private let loanJSON = Data("""
    [{
      "id": "loan-001", "device_model": "Galaxy A15", "device_image_url": null,
      "principal": "240.00", "outstanding_balance": "140.00",
      "monthly_installment": "20.00", "status": "active",
      "next_installment_due": "2026-08-10T00:00:00Z"
    }]
    """.utf8)

    @Test func successfulGETDecodesTheFixture() async throws {
        StubURLProtocol.handler = { [loanJSON] request in
            (StubURLProtocol.httpResponse(url: request.url!, status: 200), loanJSON)
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient())
        let page = try await repository.fetchLoans(page: 1)

        #expect(page.loans.count == 1)
        #expect(page.loans.first?.id == LoanID("loan-001"))
        #expect(page.loans.first?.outstandingBalance == Money(amount: 140, currencyCode: "USD"))
        #expect(!page.hasMore)
    }

    @Test func serverErrorGatesBeforeDecodeAndMaps() async {
        StubURLProtocol.handler = { request in
            // The body is an HTML error page — decoding it as loans would
            // produce a lying DecodingError; status gating must win.
            (StubURLProtocol.httpResponse(url: request.url!, status: 500), Data("<html>oops</html>".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient())
        await #expect(throws: DomainError.serverError(code: 500)) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func offlineTransportErrorMapsToOffline() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient())
        await #expect(throws: DomainError.offline) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func malformedBodyMapsToInvalidData() async {
        StubURLProtocol.handler = { request in
            (StubURLProtocol.httpResponse(url: request.url!, status: 200), Data("{not json".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient())
        do {
            _ = try await repository.fetchLoans(page: 1)
            Issue.record("expected invalidData")
        } catch let error as DomainError {
            guard case .invalidData = error else {
                Issue.record("expected invalidData, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func requestsCarryBearerAndUniqueCorrelationIDs() async throws {
        let box = RequestBox()
        StubURLProtocol.handler = { [loanJSON] request in
            box.append(request)
            return (StubURLProtocol.httpResponse(url: request.url!, status: 200), loanJSON)
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient())
        _ = try await repository.fetchLoans(page: 1)
        _ = try await repository.fetchLoans(page: 1)

        let requests = box.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        }
        let correlationIDs = requests.compactMap { $0.value(forHTTPHeaderField: "X-Correlation-ID") }
        #expect(correlationIDs.count == 2)
        #expect(correlationIDs[0] != correlationIDs[1])
    }

    @Test func paymentSubmissionCarriesTheIdempotencyKeyHeader() async throws {
        let box = RequestBox()
        StubURLProtocol.handler = { request in
            box.append(request)
            if request.httpMethod == "POST" {
                return (StubURLProtocol.httpResponse(url: request.url!, status: 201),
                        Data(#"{"id": "17"}"#.utf8))
            }
            // The follow-up loan read for the receipt's remaining balance.
            return (StubURLProtocol.httpResponse(url: request.url!, status: 200), Data("""
            {
              "id": "loan-001", "device_model": "Galaxy A15", "device_image_url": null,
              "principal": "240.00", "outstanding_balance": "140.00",
              "monthly_installment": "20.00", "status": "active",
              "next_installment_due": "2026-08-10T00:00:00Z"
            }
            """.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemotePaymentRepository(client: makeClient())
        let key = IdempotencyKey.generate()
        let receipt = try await repository.submit(PaymentRequest(
            loanID: LoanID("loan-001"),
            methodID: PaymentMethodID("pm-1"),
            amount: Money(amount: 20, currencyCode: "USD"),
            idempotencyKey: key
        ))

        let post = box.requests.first { $0.httpMethod == "POST" }
        #expect(post?.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
        #expect(post?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(receipt.paymentID == "17")
        #expect(receipt.remainingBalance == Money(amount: 120, currencyCode: "USD"))
    }

    @Test func refusedPinSurfacesAsTheDistinctDomainError() async {
        // The delegate refused the handshake (violation recorded); the
        // transport error is a generic cancellation. The client must
        // upgrade it to the DISTINCT error — telling a user to "retry on
        // better wifi" is dangerous advice for an interception.
        let pinning = CertificatePinning(pinsByHost: ["api.test.loanpay": ["pin"]])
        let delegate = PinnedSessionDelegate(pinning: pinning, logger: SilentDataLogger())
        delegate.recordViolationForTesting()

        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        defer { StubURLProtocol.handler = nil }

        let client = URLSessionAPIClient(
            baseURL: URL(string: "https://api.test.loanpay")!,
            session: StubURLProtocol.makeSession(),
            tokenProvider: { nil },
            logger: SilentDataLogger(),
            pinningDelegate: delegate
        )
        let repository = RemoteLoanRepository(client: client)

        await #expect(throws: DomainError.pinningViolation) {
            _ = try await repository.fetchLoans(page: 1)
        }
    }

    @Test func ordinaryCancellationWithoutViolationIsNotAPinningError() async {
        let delegate = PinnedSessionDelegate(
            pinning: CertificatePinning(pinsByHost: [:]),
            logger: SilentDataLogger()
        )

        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        defer { StubURLProtocol.handler = nil }

        let client = URLSessionAPIClient(
            baseURL: URL(string: "https://api.test.loanpay")!,
            session: StubURLProtocol.makeSession(),
            tokenProvider: { nil },
            logger: SilentDataLogger(),
            pinningDelegate: delegate
        )
        let repository = RemoteLoanRepository(client: client)

        // No violation was recorded → NOT a pinning error; the generic
        // path maps it like any transport failure.
        do {
            _ = try await repository.fetchLoans(page: 1)
            Issue.record("expected an error")
        } catch let error as DomainError {
            #expect(error != .pinningViolation)
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    @Test func missingTokenSendsNoAuthorizationHeader() async throws {
        let box = RequestBox()
        StubURLProtocol.handler = { [loanJSON] request in
            box.append(request)
            return (StubURLProtocol.httpResponse(url: request.url!, status: 200), loanJSON)
        }
        defer { StubURLProtocol.handler = nil }

        let repository = RemoteLoanRepository(client: makeClient(token: nil))
        _ = try await repository.fetchLoans(page: 1)

        #expect(box.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
