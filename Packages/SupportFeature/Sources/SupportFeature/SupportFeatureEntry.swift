import Foundation
import LoanPayDomain
import LoanPayFeatureKit

/// The support feature's one public doorway.
public enum SupportFeatureEntry: FeatureEntry {
    public static let featureID = "support"

    @MainActor
    public static func makeCallbackView(
        outbox: any OutboxEnqueuing,
        preselectedTopicID: String? = nil,
        loanID: LoanID? = nil
    ) -> SupportCallbackView {
        SupportCallbackView(
            viewModel: SupportCallbackViewModel(
                outbox: outbox,
                preselectedTopicID: preselectedTopicID,
                loanID: loanID
            )
        )
    }

    public static func makeDeepLinkHandler() -> some DeepLinkHandling {
        SupportDeepLinkHandler()
    }
}
