import Foundation
import LoanPayFeatureKit
import PaymentFeature

/// The one place features announce themselves to the app.
///
/// ARCH: adding a feature to the app = one line here plus its package.
/// Nothing else in the app target learns the feature exists — the
/// dispatcher gets a handler under a prefix, and later registrations
/// (debug menu sections, flag inventories) will flow through the same
/// funnel.
@MainActor
enum FeatureRegistration {
    static func registerAll(dispatcher: DeepLinkDispatcher) {
        dispatcher.register(featureID: "loans", handler: LoansDeepLinkHandler())
        dispatcher.register(featureID: PaymentFeatureEntry.featureID, handler: PaymentDeepLinkHandler())
    }
}
