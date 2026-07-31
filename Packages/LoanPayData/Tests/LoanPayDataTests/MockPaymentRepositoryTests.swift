import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

@Suite struct MockPaymentRepositoryTests {
    private func makeRequest(key: IdempotencyKey) -> PaymentRequest {
        PaymentRequest(
            loanID: LoanID("loan-001"),
            methodID: PaymentMethodID("pm-wallet-mpesa"),
            amount: Money(amount: 20, currencyCode: "USD"),
            idempotencyKey: key
        )
    }

    @Test func paymentMethodsDecodeFromFixture() async throws {
        let repository = MockPaymentRepository(behavior: makeInstantBehavior(), sleeper: RecordingSleeper())
        let methods = try await repository.fetchPaymentMethods(for: LoanID("loan-001"))
        #expect(methods.count == 3)
        #expect(Set(methods.map(\.kind)) == [.bankCard, .mobileWallet, .cashAgent])
    }

    @Test func replayedIdempotencyKeyReturnsTheOriginalReceipt() async throws {
        let repository = MockPaymentRepository(behavior: makeInstantBehavior(), sleeper: RecordingSleeper())
        let key = IdempotencyKey.generate()

        let first = try await repository.submit(makeRequest(key: key))
        let replay = try await repository.submit(makeRequest(key: key))

        // FINTECH: byte-identical outcome — the replay minted no second
        // payment, it surfaced the first one.
        #expect(replay == first)
    }

    @Test func distinctKeysMintDistinctPayments() async throws {
        let repository = MockPaymentRepository(behavior: makeInstantBehavior(), sleeper: RecordingSleeper())

        let first = try await repository.submit(makeRequest(key: .generate()))
        let second = try await repository.submit(makeRequest(key: .generate()))

        #expect(first.paymentID != second.paymentID)
    }

    @Test func replayWinsEvenWhileTheEndpointIsFailing() async throws {
        let behavior = makeInstantBehavior()
        let repository = MockPaymentRepository(behavior: behavior, sleeper: RecordingSleeper())
        let key = IdempotencyKey.generate()
        let original = try await repository.submit(makeRequest(key: key))

        // The endpoint now times out for NEW submissions…
        await behavior.setFailure(.httpStatus(504), for: .submitPayment)

        // …but the replayed key still answers with the settled receipt,
        // like a real idempotent server that already processed it.
        let replay = try await repository.submit(makeRequest(key: key))
        #expect(replay == original)

        await #expect(throws: DomainError.serverError(code: 504)) {
            _ = try await repository.submit(makeRequest(key: .generate()))
        }
    }

    @Test func unauthorizedInjectionMapsToUnauthorized() async throws {
        let behavior = makeInstantBehavior()
        await behavior.setFailure(.httpStatus(401), for: .submitPayment)
        let repository = MockPaymentRepository(behavior: behavior, sleeper: RecordingSleeper())

        await #expect(throws: DomainError.unauthorized) {
            _ = try await repository.submit(makeRequest(key: .generate()))
        }
    }
}
