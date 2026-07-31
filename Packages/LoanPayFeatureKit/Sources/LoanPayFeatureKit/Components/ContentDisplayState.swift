import Foundation

/// The four display shapes every loading screen shares.
///
/// LANG: deliberately a TOP-LEVEL type, not nested in StateContainer.
/// Nested types inside a generic are specialized with it —
/// `StateContainer<A>.DisplayState` and `StateContainer<B>.DisplayState`
/// would be different, incompatible types, forcing every screen to name its
/// content type just to describe its state. Hoisting the enum keeps "what
/// state am I in" independent of "what do I render".
///
/// ARCH: this is a *display* state, deliberately poorer than any
/// ViewModel's state enum — no associated data beyond what rendering needs,
/// no domain types. ViewModels translate rich state down to it.
public enum ContentDisplayState: Equatable {
    case loading
    case content
    case empty(title: String, message: String)
    case error(message: String, isRetryable: Bool)
}
