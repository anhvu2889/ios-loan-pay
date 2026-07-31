import Foundation

// ARCH: The ONE error vocabulary the presentation layer is allowed to see.
// URLError, HTTP status codes and DecodingError are transport dialects; they
// are translated into this enum exactly once, at the data-layer boundary
// (ErrorMapper). A ViewModel that switches on URLError.Code has punched a
// hole through the architecture — and will break the day the transport
// changes.
public enum DomainError: Error, Hashable, Sendable {
    case offline
    case timeout
    case unauthorized
    case notFound
    case serverError(code: Int)
    // FINTECH: carries the key path of the malformed field ONLY — never the
    // value. Payload values here are loan amounts and borrower data; an
    // error that embeds them would leak PII into logs and crash reports.
    case invalidData(keyPath: String)
    // FINTECH: certificate pinning failed — the server's key is not one of
    // ours. DISTINCT from other network errors on purpose: "retry on better
    // wifi" is the right advice for a timeout and DANGEROUS advice here,
    // where the likely causes are a hostile network or our own botched
    // certificate rotation. Distinct case → distinct message → distinct
    // alerting.
    case pinningViolation
    case unknown

    /// Copy safe to show a borrower. Deliberately free of transport jargon.
    public var userMessage: String {
        switch self {
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timeout:
            return "This is taking longer than expected. Please try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "We couldn't find what you were looking for."
        case .serverError:
            return "Something went wrong on our side. Please try again shortly."
        case .invalidData:
            return "We received an unexpected response. Please try again shortly."
        case .pinningViolation:
            return "We couldn't verify the secure connection to LoanPay. If you're on public Wi-Fi, switch to mobile data and try again."
        case .unknown:
            return "Something unexpected happened. Please try again."
        }
    }

    // WHY: retry-ability is a property of the *error*, decided once here —
    // not re-derived ad hoc by every screen. Transient conditions (network,
    // 5xx, timeouts) are retryable; unauthorized needs re-auth, notFound and
    // malformed payloads will fail identically on every attempt.
    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .serverError, .unknown:
            return true
        // WHY pinning is non-retryable: hammering a connection whose
        // identity we rejected only gives an interceptor more chances.
        case .unauthorized, .notFound, .invalidData, .pinningViolation:
            return false
        }
    }
}
