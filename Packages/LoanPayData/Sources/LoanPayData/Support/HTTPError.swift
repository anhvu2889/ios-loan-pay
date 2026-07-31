import Foundation

/// A non-2xx HTTP response, thrown by transport code BEFORE any decoding is
/// attempted. Exists so status handling is explicit and mappable — trying to
/// decode an error body as a success DTO produces a misleading
/// DecodingError instead of the truth.
public struct HTTPError: Error, Hashable, Sendable {
    public let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}
