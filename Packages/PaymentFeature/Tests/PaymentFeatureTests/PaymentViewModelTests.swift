import Foundation
import Testing
import LoanPayDomain
@testable import PaymentFeature

@MainActor
@Suite struct PaymentViewModelTests {
    private func makeViewModel(
        loanRepository: StubLoanRepository = StubLoanRepository(),
        paymentRepository: SpyPaymentRepository = SpyPaymentRepository(),
        flags: TestFlags = TestFlags(),
        analytics: RecordingAnalytics = RecordingAnalytics()
    ) -> PaymentViewModel {
        PaymentViewModel(
            loanID: LoanID("loan-1"),
            loanRepository: loanRepository,
            paymentRepository: paymentRepository,
            flags: flags,
            analytics: analytics,
            logger: NullLogger()
        )
    }

    /// Drives a fresh view model to `.ready`.
    private func makeReadyViewModel(
        paymentRepository: SpyPaymentRepository = SpyPaymentRepository(),
        analytics: RecordingAnalytics = RecordingAnalytics()
    ) async -> PaymentViewModel {
        let viewModel = makeViewModel(paymentRepository: paymentRepository, analytics: analytics)
        viewModel.send(.start)
        await viewModel.loadTask?.value
        return viewModel
    }

    // MARK: - Context load

    @Test func contextLoadsBothHalvesAndPreselectsAMethod() async {
        let viewModel = await makeReadyViewModel()

        guard case .ready(let context) = viewModel.state else {
            Issue.record("expected ready, got \(viewModel.state)")
            return
        }
        #expect(context.methods.count == 2)
        #expect(context.selectedMethodID == PaymentMethodID("pm-1"))
        #expect(context.amount == usd("20.00"))
        // No key exists until the user commits to paying.
        #expect(viewModel.idempotencyKey == nil)
    }

    @Test func contextFailsAsAUnitWhenEitherHalfFails() async {
        let viewModel = makeViewModel(
            paymentRepository: SpyPaymentRepository(methodsScript: [.failure(.serverError(code: 500))])
        )
        viewModel.send(.start)
        await viewModel.loadTask?.value

        // Detail succeeded, methods failed → the whole context fails.
        #expect(viewModel.state == .loadFailed(.serverError(code: 500)))
    }

    @Test func unauthorizedDuringLoadExpiresTheSession() async {
        let viewModel = makeViewModel(
            paymentRepository: SpyPaymentRepository(methodsScript: [.failure(.unauthorized)])
        )
        viewModel.send(.start)
        await viewModel.loadTask?.value

        #expect(viewModel.state == .sessionExpired)
    }

    @Test func retryFromLoadFailureReloadsWithoutTouchingAnyKey() async {
        let viewModel = makeViewModel(
            paymentRepository: SpyPaymentRepository(methodsScript: [
                .failure(.timeout),
                .success(testMethods),
            ])
        )
        viewModel.send(.start)
        await viewModel.loadTask?.value
        #expect(viewModel.state == .loadFailed(.timeout))

        viewModel.send(.retry)
        await viewModel.loadTask?.value

        guard case .ready = viewModel.state else {
            Issue.record("expected ready after retry")
            return
        }
        // No payment was ever attempted, so no key exists.
        #expect(viewModel.idempotencyKey == nil)
    }

    // MARK: - The double-tap

    @Test func doubleTapSubmitsExactlyOneRepositoryCall() async {
        let gate = Gate()
        let repository = SpyPaymentRepository(submitGate: gate)
        let viewModel = await makeReadyViewModel(paymentRepository: repository)

        // Two taps land back to back. The FIRST send transitions to
        // .paying synchronously; the second .pay finds .paying and dies in
        // the state machine's default case.
        viewModel.send(.pay)
        viewModel.send(.pay)

        await gate.waitForEntries(1)
        await #expect(repository.submissions.count == 1)

        await gate.open()
        await viewModel.payTask?.value

        guard case .success = viewModel.state else {
            Issue.record("expected success, got \(viewModel.state)")
            return
        }
        // Still exactly one submission after everything settled.
        await #expect(repository.submissions.count == 1)
    }

    // MARK: - Idempotency key lifecycle

    @Test func retryAfterTimeoutReusesTheByteIdenticalKey() async {
        let repository = SpyPaymentRepository(submissionScript: [
            .failure(.timeout),
        ])
        let viewModel = await makeReadyViewModel(paymentRepository: repository)

        viewModel.send(.pay)
        await viewModel.payTask?.value
        guard case .failed(_, .timeout) = viewModel.state else {
            Issue.record("expected failed(timeout), got \(viewModel.state)")
            return
        }
        let keyAfterFailure = viewModel.idempotencyKey
        #expect(keyAfterFailure != nil)

        viewModel.send(.retry)
        await viewModel.payTask?.value

        let submissions = await repository.submissions
        #expect(submissions.count == 2)
        // FINTECH: the whole point — the retry presents the SAME bytes, so
        // a server that already settled the "failed" attempt answers with
        // the original receipt instead of charging twice.
        #expect(submissions[0].idempotencyKey == submissions[1].idempotencyKey)
        #expect(submissions[1].idempotencyKey == keyAfterFailure)
        guard case .success = viewModel.state else {
            Issue.record("expected success after retry")
            return
        }
    }

    @Test func successConsumesTheKeyAndANewIntentMintsANewOne() async {
        let repository = SpyPaymentRepository()
        let first = await makeReadyViewModel(paymentRepository: repository)
        first.send(.pay)
        await first.payTask?.value
        guard case .success = first.state else {
            Issue.record("expected success")
            return
        }
        // The intent is consumed; its key dies with it.
        #expect(first.idempotencyKey == nil)

        // A brand-new payment intent (fresh flow) gets a fresh key.
        let second = await makeReadyViewModel(paymentRepository: repository)
        second.send(.pay)
        await second.payTask?.value

        let submissions = await repository.submissions
        #expect(submissions.count == 2)
        #expect(submissions[0].idempotencyKey != submissions[1].idempotencyKey)
    }

    // MARK: - Dismissal

    @Test func dismissMidPaymentCancelsFreezesAndClearsTheKey() async {
        let gate = Gate()
        let repository = SpyPaymentRepository(submitGate: gate)
        let viewModel = await makeReadyViewModel(paymentRepository: repository)

        viewModel.send(.pay)
        await gate.waitForEntries(1)

        viewModel.send(.dismiss)

        // Frozen at .paying: dismissal is not a transition, it is a stop.
        guard case .paying = viewModel.state else {
            Issue.record("expected frozen .paying, got \(viewModel.state)")
            return
        }
        #expect(viewModel.idempotencyKey == nil)

        // The in-flight submission observed real cancellation…
        await viewModel.payTask?.value
        await #expect(repository.cancelledSubmissionCount == 1)

        // …and NOTHING mutates after dismissal: the completion was blocked
        // and further actions are ignored.
        guard case .paying = viewModel.state else {
            Issue.record("state mutated after dismissal")
            return
        }
        viewModel.send(.pay)
        viewModel.send(.retry)
        await #expect(repository.submissions.count == 1)
    }

    // MARK: - Session expiry

    @Test func unauthorizedDuringPaymentExpiresSessionAndClearsKey() async {
        let repository = SpyPaymentRepository(submissionScript: [.failure(.unauthorized)])
        let analytics = RecordingAnalytics()
        let viewModel = await makeReadyViewModel(paymentRepository: repository, analytics: analytics)

        viewModel.send(.pay)
        await viewModel.payTask?.value

        #expect(viewModel.state == .sessionExpired)
        #expect(viewModel.idempotencyKey == nil)
        #expect(analytics.events.contains(.paymentFailed(errorType: "unauthorized")))
    }

    // MARK: - Kill switch

    @Test func killSwitchOffShowsMaintenanceAndPayIsANoOp() async {
        let loanRepository = StubLoanRepository()
        let repository = SpyPaymentRepository()
        let viewModel = makeViewModel(
            loanRepository: loanRepository,
            paymentRepository: repository,
            flags: TestFlags(paymentsEnabled: false)
        )

        viewModel.send(.start)

        #expect(viewModel.state == .maintenance)
        // Nothing was even fetched — the switch gates the whole flow.
        await #expect(loanRepository.detailFetchCount == 0)

        viewModel.send(.pay)
        #expect(viewModel.state == .maintenance)
        await #expect(repository.submissions.isEmpty)
    }

    // MARK: - Method selection & funnel

    @Test func selectingAMethodUpdatesTheContext() async {
        let viewModel = await makeReadyViewModel()

        viewModel.send(.selectMethod(PaymentMethodID("pm-2")))

        guard case .ready(let context) = viewModel.state else {
            Issue.record("expected ready")
            return
        }
        #expect(context.selectedMethodID == PaymentMethodID("pm-2"))
    }

    @Test func happyPathEmitsTheFunnelInOrder() async {
        let analytics = RecordingAnalytics()
        let viewModel = await makeReadyViewModel(analytics: analytics)

        viewModel.send(.pay)
        await viewModel.payTask?.value

        #expect(analytics.events == [
            .paymentViewed,
            .paymentStarted,
            .paymentSubmitted,
            .paymentSucceeded,
        ])
    }
}
