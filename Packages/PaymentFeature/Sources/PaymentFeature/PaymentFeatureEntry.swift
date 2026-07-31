import Foundation
import LoanPayDomain
import LoanPayFeatureKit

/// The payment feature's ONE public doorway.
///
/// ARCH: the app composes this feature by calling `makeFlowView` with
/// domain seams from its composition root. Nothing else in this package is
/// visible to the app beyond the flow view and its outcome — the state
/// machine, subviews and context are implementation detail, free to change
/// without touching app code.
public enum PaymentFeatureEntry: FeatureEntry {
    public static let featureID = "payment"

    @MainActor
    public static func makeFlowView(
        loanID: LoanID,
        loanRepository: any LoanRepository,
        paymentRepository: any PaymentRepository,
        flags: any FeatureFlags,
        analytics: any AnalyticsClient,
        logger: any AppLogger,
        onFinished: @escaping (PaymentOutcome) -> Void
    ) -> PaymentFlowView {
        PaymentFlowView(
            viewModel: PaymentViewModel(
                loanID: loanID,
                loanRepository: loanRepository,
                paymentRepository: paymentRepository,
                flags: flags,
                analytics: analytics,
                logger: logger
            ),
            onFinished: onFinished
        )
    }
}
