import Foundation

/// A feature handler's verdict on its slice of a deep link.
public enum DeepLinkOutcome: Equatable, Sendable {
    /// Parsed and executable right now.
    case handled(NavigationIntent)
    /// Parsed, but the destination is behind the login wall — the app
    /// stores the intent and replays it once (and only once) after auth.
    case requiresAuth(NavigationIntent)
    /// Not a link this feature understands. The dispatcher logs and DROPS
    /// it — an unrecognized link must never guess at a destination.
    case notRecognized
}
