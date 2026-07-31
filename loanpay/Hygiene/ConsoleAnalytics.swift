import Foundation
import LoanPayDomain

/// Stand-in analytics backend: prints the funnel to the console (DEBUG
/// only). The interesting part is the *shape* — the app tracks through
/// `AnalyticsClient`, so swapping in a real vendor SDK later touches one
/// file and zero call sites.
struct ConsoleAnalytics: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        // FINTECH: events carry no amounts and no identifiers by
        // construction (see AnalyticsEvent). If this line ever prints a
        // balance, the bug is in the event enum, not here.
        #if DEBUG
        print("[analytics] \(event)")
        #endif
    }
}
