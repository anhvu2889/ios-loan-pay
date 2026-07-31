import Foundation
import Observation
import LoanPayDomain

/// The payment state machine. This type is the codebase's exemplar for
/// "complex flow": ONE state enum, ONE synchronous `send`, async work in
/// private owned tasks that report back through `send`.
@Observable
@MainActor
public final class PaymentViewModel {
    public private(set) var state: PaymentState = .loading

    // FINTECH — the idempotency key lifecycle, the heart of this file:
    //   • minted on the FIRST .pay of an intent (not at init, not per HTTP
    //     attempt),
    //   • reused BYTE-IDENTICALLY by .retry from .failed — a timeout may
    //     have landed server-side, and the same key is what lets the server
    //     answer "already done" instead of charging twice,
    //   • untouched by .retry from .loadFailed (no payment was attempted),
    //   • cleared on success (the intent is consumed; the NEXT payment is a
    //     new intent and must get a new key),
    //   • cleared on dismiss and on session expiry (the intent is
    //     abandoned; resurrecting its key later could collide with a
    //     server-side dedupe window).
    private(set) var idempotencyKey: IdempotencyKey?

    // WHY owned handles: the flow must be able to stop its own async work
    // (dismiss cancels; a new load replaces). Fire-and-forget tasks can't
    // be stopped by anyone.
    private(set) var loadTask: Task<Void, Never>?
    private(set) var payTask: Task<Void, Never>?

    /// Set on .dismiss. Every entry to `send` checks it: the sheet is gone,
    /// and a state machine nobody can see must not keep transitioning —
    /// "frozen" is a testable guarantee, not a hope.
    private var isDismissed = false

    let loanID: LoanID
    private let loanRepository: any LoanRepository
    private let paymentRepository: any PaymentRepository
    private let flags: any FeatureFlags
    private let analytics: any AnalyticsClient
    private let logger: any AppLogger

    public init(
        loanID: LoanID,
        loanRepository: any LoanRepository,
        paymentRepository: any PaymentRepository,
        flags: any FeatureFlags,
        analytics: any AnalyticsClient,
        logger: any AppLogger
    ) {
        self.loanID = loanID
        self.loanRepository = loanRepository
        self.paymentRepository = paymentRepository
        self.flags = flags
        self.analytics = analytics
        self.logger = logger
    }

    // MARK: - The single door

    // WHY synchronous: `send` runs start-to-finish on the main actor with
    // no suspension point, so no second action can interleave mid-
    // transition. The classic double-tap race — two .pay actions reading
    // the same "ready" state — cannot happen, because the first send
    // completes its transition to .paying before the second is processed.
    // The branch count IS the state machine: every legal (state, action)
    // pair, in one switch, with no suspension points. Extracting branches
    // into helpers would preserve the number while hiding the shape — the
    // exhaustive switch in one screenful is the safety feature.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func send(_ action: PaymentAction) {
        guard !isDismissed else { return }

        switch (state, action) {
        // MARK: Lifecycle
        case (.loading, .start):
            guard flags.isEnabled(.paymentsEnabled) else {
                // FINTECH: the kill switch renders a deliberate maintenance
                // state, not an error — "we turned this off" and "something
                // broke" deserve different screens and different support
                // call volumes.
                state = .maintenance
                return
            }
            analytics.track(.paymentViewed)
            startContextLoad()

        case (.loading, .contextLoaded(let context)):
            state = .ready(context)

        case (.loading, .contextLoadFailed(.unauthorized)):
            // The session died before any payment was attempted; no key
            // exists to clear, and the app takes over for re-auth.
            state = .sessionExpired

        case (.loading, .contextLoadFailed(let error)):
            state = .loadFailed(error)

        case (.loadFailed, .retry):
            // WHY the key is untouched here: no payment was ever submitted
            // from this flow, so there is no intent to protect. (It is nil
            // by construction — minting happens at .pay.)
            state = .loading
            startContextLoad()

        // MARK: Method selection
        case (.ready(var context), .selectMethod(let methodID)):
            context.selectedMethodID = methodID
            state = .ready(context)

        // MARK: Paying
        case (.ready(let context), .pay):
            guard flags.isEnabled(.paymentsEnabled) else { return } // kill switch: no-op
            guard context.selectedMethodID != nil else { return }
            // First .pay of this intent mints the key; a re-entry through
            // .failed → .retry arrives with the key already set.
            if idempotencyKey == nil {
                idempotencyKey = .generate()
            }
            analytics.track(.paymentStarted)
            state = .paying(context)
            startSubmission(context)

        // LANG: this case IS the double-tap defense. A second .pay finds
        // the state already .paying; (paying, .pay) matches nothing below
        // and lands in the default no-op. One tap, one transition, one
        // submission — enforced by pattern matching, not by disabling
        // buttons fast enough.

        case (.paying, .paymentSucceeded(let receipt)):
            // Success consumes the intent: the key dies WITH it, so a
            // future payment can never accidentally replay this one.
            idempotencyKey = nil
            analytics.track(.paymentSucceeded)
            state = .success(receipt)

        case (.paying, .paymentFailed(.unauthorized)):
            // FINTECH: 401 kills the session, and the abandoned intent's
            // key goes with it — after re-auth the user starts a fresh
            // intent with a fresh key.
            idempotencyKey = nil
            analytics.track(.paymentFailed(errorType: "unauthorized"))
            state = .sessionExpired

        case (.paying(let context), .paymentFailed(let error)):
            analytics.track(.paymentFailed(errorType: errorTypeName(error)))
            state = .failed(context, error)

        case (.failed(let context, _), .retry):
            // FINTECH: THE critical transition. No new key is minted —
            // `startSubmission` reuses `idempotencyKey` byte-for-byte. If
            // the failed attempt actually landed (timeouts lie), the server
            // recognizes the key and returns the original receipt instead
            // of double-charging. This is also why payments NEVER auto-
            // retry: only a human, seeing the failure, may resubmit.
            analytics.track(.paymentStarted)
            state = .paying(context)
            startSubmission(context)

        // MARK: Dismissal
        case (_, .dismiss):
            // Owned-task cancellation: whatever is in flight stops caring.
            // The repository call gets CancellationError; its completion
            // never reaches `send` (isDismissed) — the state is frozen
            // exactly where dismissal found it.
            loadTask?.cancel()
            payTask?.cancel()
            idempotencyKey = nil
            isDismissed = true

        default:
            // WHY a logged no-op instead of assertionFailure: unexpected
            // (state, action) pairs in production are race artifacts (a
            // stale completion, a queued tap). Crashing a PAYMENT screen
            // over one is strictly worse than ignoring it; the log line
            // keeps them countable.
            logger.log(.debug, category: .payment, "ignored action in current state")
        }
    }

    // MARK: - Owned async work

    private func startContextLoad() {
        loadTask = Task { [loanRepository, paymentRepository, loanID] in
            do {
                // MODERN: `async let` runs both requests concurrently and
                // fails together — if either throws, the other is cancelled
                // and the whole context load fails as a unit. (Pre-
                // concurrency this was a DispatchGroup with two result
                // boxes and a merge.) WHY fail-together: a payment screen
                // with a loan but no methods is not "partially useful", it
                // is a dead end with extra steps.
                async let detail = loanRepository.fetchLoanDetail(id: loanID)
                async let methods = paymentRepository.fetchPaymentMethods(for: loanID)
                let context = PaymentContext(detail: try await detail, methods: try await methods)
                self.send(.contextLoaded(context))
            } catch is CancellationError {
                // Dismissed mid-load; the frozen state stands.
            } catch let error as DomainError {
                self.send(.contextLoadFailed(error))
            } catch {
                self.send(.contextLoadFailed(.unknown))
            }
        }
    }

    private func startSubmission(_ context: PaymentContext) {
        guard let key = idempotencyKey, let methodID = context.selectedMethodID else {
            // Unreachable by construction (checked at .pay/.retry); logged
            // rather than crashed for the same reason as the default case.
            logger.log(.error, category: .payment, "submission without key or method")
            return
        }
        let request = PaymentRequest(
            loanID: context.detail.loan.id,
            methodID: methodID,
            amount: context.amount,
            idempotencyKey: key
        )
        analytics.track(.paymentSubmitted)
        payTask = Task { [paymentRepository] in
            do {
                let receipt = try await paymentRepository.submit(request)
                self.send(.paymentSucceeded(receipt))
            } catch is CancellationError {
                // Dismissal cancelled us; isDismissed already blocks sends.
            } catch let error as DomainError {
                self.send(.paymentFailed(error))
            } catch {
                self.send(.paymentFailed(.unknown))
            }
        }
    }

    // FINTECH: analytics gets the error TYPE, never the message — messages
    // can grow payload details; type names cannot.
    private func errorTypeName(_ error: DomainError) -> String {
        switch error {
        case .offline: "offline"
        case .timeout: "timeout"
        case .unauthorized: "unauthorized"
        case .notFound: "notFound"
        case .serverError: "serverError"
        case .invalidData: "invalidData"
        case .pinningViolation: "pinningViolation"
        case .unknown: "unknown"
        }
    }
}
