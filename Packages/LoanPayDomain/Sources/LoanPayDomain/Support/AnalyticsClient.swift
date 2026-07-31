import Foundation

// FINTECH: the payment funnel carries NO amounts, NO loan ids, NO method
// details. `paymentFailed` records only the error *type* — enough to alert
// on a spike of timeouts without ever shipping a borrower's balance to an
// analytics pipeline.
public enum AnalyticsEvent: Equatable, Sendable {
    case paymentViewed
    case paymentStarted
    case paymentSubmitted
    case paymentSucceeded
    case paymentFailed(errorType: String)
}

public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}
