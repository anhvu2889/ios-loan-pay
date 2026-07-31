import Foundation
import LoanPayDomain

/// Analytics for previews: a black hole. A preview canvas must never emit
/// funnel events — dashboards should reflect users, not developers.
public struct PreviewAnalytics: AnalyticsClient {
    public init() {}

    public func track(_ event: AnalyticsEvent) {}
}
