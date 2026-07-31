import Foundation
import LoanPayDomain

/// The payment flow's single source of truth.
///
/// WHY one enum instead of flags: `isLoading` + `error` + `isPaying` +
/// `receipt` can encode 16 combinations, of which maybe six are meaningful
/// — the other ten are bugs waiting for a render. An enum with associated
/// values makes ONLY the meaningful shapes representable, and the compiler
/// audits every switch when a state is added.
public enum PaymentState: Equatable, Sendable {
    case loading
    case loadFailed(DomainError)
    case ready(PaymentContext)
    case paying(PaymentContext)
    case failed(PaymentContext, DomainError)
    /// The server said 401: this session is dead. Terminal here — the app
    /// tears the sheet down and routes through re-auth.
    case sessionExpired
    case success(PaymentReceipt)
    /// The payments kill switch is off. Not an error — a deliberate,
    /// remotely-operated state with its own honest screen.
    case maintenance
}
