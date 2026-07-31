import Foundation

/// Shared validation for identifier-shaped deep-link parameters.
public enum DeepLinkParameter {
    // FINTECH: deep links are UNTRUSTED INPUT — any app on the device can
    // open loanpay:// URLs. Identifiers are allow-listed to alphanumerics
    // plus hyphen and length-capped BEFORE they reach repositories or
    // logs: no traversal shapes (../), no injection payloads, no megabyte
    // "ids" burning memory. Validation is shared here so no feature
    // hand-rolls a weaker version.
    private static let maxLength = 64

    public static func identifier(_ raw: String) -> String? {
        guard !raw.isEmpty,
              raw.count <= maxLength,
              raw.wholeMatch(of: /[A-Za-z0-9-]+/) != nil else {
            return nil
        }
        return raw
    }
}
