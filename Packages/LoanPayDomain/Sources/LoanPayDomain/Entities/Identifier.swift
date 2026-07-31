import Foundation

// LANG: A phantom-typed identifier. `Entity` is never stored — it exists only
// in the type signature so that `Identifier<Loan>` and
// `Identifier<PaymentMethod>` are distinct, incompatible types. Passing a
// payment-method id where a loan id is expected becomes a compile error
// instead of a production bug. A bare `String` id gives up that safety; a
// per-entity hand-written struct duplicates this code N times.
public struct Identifier<Entity>: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// LANG: Codable is written by hand so the wire/persisted form is a bare
// string ("loan-42"), not a nested object ({"rawValue":"loan-42"}). The
// synthesized conformance would produce the latter and silently couple our
// storage format to an implementation detail of this struct.
extension Identifier: Codable {
    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
