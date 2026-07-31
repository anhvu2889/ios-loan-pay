import Foundation
import LoanPayDomain

/// Shared control panel for the in-process mock backend: base latency plus
/// one optional injected failure per endpoint. The debug menu mutates this
/// at runtime; repositories consult it before serving anything.
///
/// LANG: an actor, not a class with a lock — it is mutated from the debug
/// menu (MainActor) while repositories read it from arbitrary tasks.
/// Actor isolation makes the races unrepresentable instead of unlikely.
public actor MockBehavior {
    /// What the repository should do after the preflight checks pass.
    public enum Directive: Sendable, Equatable {
        case proceed
        /// Serve a syntactically broken payload so the *decode* path fails —
        /// the failure must travel through JSONDecoder and ErrorMapper
        /// exactly like real backend corruption, not shortcut around them.
        case serveMalformedPayload
    }

    private var failures: [MockEndpoint: InjectedFailure] = [:]
    private var latency: Duration
    private var flakinessRNG: SplitMix64

    public init(latency: Duration = .milliseconds(400), flakinessSeed: UInt64 = 0x10A2) {
        self.latency = latency
        self.flakinessRNG = SplitMix64(seed: flakinessSeed)
    }

    public func setFailure(_ failure: InjectedFailure?, for endpoint: MockEndpoint) {
        failures[endpoint] = failure
    }

    public func failure(for endpoint: MockEndpoint) -> InjectedFailure? {
        failures[endpoint]
    }

    public func setLatency(_ duration: Duration) {
        latency = duration
    }

    /// Applies latency and the endpoint's injected failure, if any.
    ///
    /// WHY the thrown errors are *transport* types (URLError, HTTPError) and
    /// not DomainError: injected failures must exercise the same
    /// ErrorMapper path production failures take. A mock that throws
    /// ready-made domain errors would leave the mapper untested exactly
    /// where it matters.
    public func preflight(_ endpoint: MockEndpoint, sleeper: any Sleeper) async throws -> Directive {
        try await sleeper.sleep(for: latency)

        switch failures[endpoint] {
        case .none:
            return .proceed
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .httpStatus(let code):
            throw HTTPError(statusCode: code)
        case .malformedJSON:
            return .serveMalformedPayload
        case .flaky(let rate):
            if Double.random(in: 0..<1, using: &flakinessRNG) < rate {
                throw URLError(.networkConnectionLost)
            }
            return .proceed
        case .slow(let seconds):
            try await sleeper.sleep(for: .milliseconds(Int64(seconds * 1000)))
            return .proceed
        }
    }
}

// WHY a seeded generator: `.flaky(rate:)` must be reproducible — a bug
// report that says "fails every third call with seed 42" can be replayed;
// SystemRandomNumberGenerator cannot.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}
