import Foundation
import LoanPayDomain

// WHY named constants instead of inline strings: accessibility identifiers
// are load-bearing API for UI tests — a typo in a string literal fails a
// test run at minute 20, a typo in a constant fails at compile time. One
// namespace also makes "what is automatable?" greppable.
public enum AccessibilityID {
    public static let loanList = "loan_list"
    public static let loanListSearchField = "loan_list_search_field"
    public static let portfolioSummaryHeader = "portfolio_summary_header"
    public static let listRetryButton = "list_retry_button"
    public static let payButton = "pay_button"
    public static let paymentMethodPicker = "payment_method_picker"
    public static let paymentRetryButton = "payment_retry_button"
    public static let applicationSubmitButton = "application_submit_button"
    public static let syncBadge = "sync_badge"

    public static func loanRow(_ id: LoanID) -> String {
        "loan_row_\(id.rawValue)"
    }
}
