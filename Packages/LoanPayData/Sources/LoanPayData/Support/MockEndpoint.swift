import Foundation

/// The mock backend's routing table — one case per simulated endpoint, so
/// failure injection can target exactly one code path (e.g. detail loads
/// fail while the list keeps working, which is how real outages look).
public enum MockEndpoint: String, CaseIterable, Sendable {
    case loanList
    case loanDetail
    case payoffQuote
    case search
    case paymentMethods
    case submitPayment
    case submitApplication
    case supportCallback
}
