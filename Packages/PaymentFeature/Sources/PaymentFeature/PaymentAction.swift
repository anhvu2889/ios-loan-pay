import Foundation
import LoanPayDomain

/// Every way the payment state machine can be poked — user intents and
/// async-work completions alike.
///
/// WHY completions are actions too: routing `contextLoaded` and
/// `paymentFailed` through the same synchronous `send` as button taps
/// means there is exactly ONE place state transitions happen. An async
/// callback that mutates state directly would be a second, unguarded door.
public enum PaymentAction: Sendable {
    case start
    case contextLoaded(PaymentContext)
    case contextLoadFailed(DomainError)
    case selectMethod(PaymentMethodID)
    case pay
    case paymentSucceeded(PaymentReceipt)
    case paymentFailed(DomainError)
    case retry
    case dismiss
}
