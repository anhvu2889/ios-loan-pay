import Foundation

/// Failure modes the debug menu can inject per endpoint.
public enum InjectedFailure: Equatable, Sendable {
    case offline
    case httpStatus(Int)
    case malformedJSON
    /// Fails a fraction of calls at `rate` (0...1), deterministic per seed.
    case flaky(rate: Double)
    case slow(seconds: Double)
}
