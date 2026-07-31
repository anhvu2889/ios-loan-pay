import Foundation

/// Loads the mock backend's dataset from bundled JSON.
enum MockFixtures {
    // LANG: a factory function, not a `static let` — JSONDecoder is a
    // mutable reference type and not Sendable, so a shared instance would be
    // an invisible data race under concurrent decodes. A fresh decoder per
    // decode is cheap and provably safe.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // MODERN: key strategy replaces hand-written CodingKeys for every
        // snake_case field; the DTO property names stay Swift-idiomatic.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }

    /// Syntactically broken JSON, served when `.malformedJSON` is injected —
    /// it must fail inside JSONDecoder so the DecodingError → DomainError
    /// path is exercised end to end.
    static var malformedData: Data {
        Data(#"{"loans": [{"id": "loan-0"#.utf8)
    }
}
