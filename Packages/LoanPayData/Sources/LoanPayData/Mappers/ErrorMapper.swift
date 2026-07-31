import Foundation
import LoanPayDomain

// ARCH: THE translation point between transport dialects and the domain's
// error vocabulary — the only place in the codebase that is allowed to
// mention URLError, HTTP status codes, or DecodingError alongside
// DomainError. Every repository (mock and real alike) funnels through
// `mapping`, so ViewModels can switch on DomainError and nothing else.
public enum ErrorMapper {
    /// Runs `work`, translating any thrown error into a `DomainError`.
    ///
    /// WHY cancellation passes through untranslated: CancellationError is
    /// not a failure, it is the caller saying "stop". Converting it to
    /// `.unknown` would make an abandoned screen render an error banner the
    /// user never should have seen.
    ///
    /// MODERN: the `isolated (any Actor)? = #isolation` parameter makes this
    /// helper isolation-polymorphic — called from an actor it stays ON that
    /// actor, so the closure may touch actor state without hopping (pre-SE-
    /// 0420 the options were marking `work` @Sendable and forfeiting actor
    /// state, or duplicating this helper on every actor).
    public static func mapping<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw domainError(from: error)
        }
    }

    // The complexity IS the function: one exhaustive translation table from
    // every transport dialect to the domain vocabulary. Splitting it into
    // helpers would scatter the one place this mapping is allowed to live.
    // swiftlint:disable:next cyclomatic_complexity
    public static func domainError(from error: any Error) -> DomainError {
        switch error {
        // WHY first: repositories sometimes throw domain errors directly
        // (e.g. a mapper's invalidData); re-mapping would erase the detail.
        case let domain as DomainError:
            return domain

        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            default:
                return .unknown
            }

        case let http as HTTPError:
            switch http.statusCode {
            case 401: return .unauthorized
            case 404: return .notFound
            case 500...599: return .serverError(code: http.statusCode)
            default: return .unknown
            }

        case let decoding as DecodingError:
            return .invalidData(keyPath: Self.keyPath(from: decoding))

        default:
            return .unknown
        }
    }

    // FINTECH: extract the coding path ONLY — a DecodingError's debug
    // description embeds raw payload fragments, which for us means amounts
    // and borrower data. The key path is diagnostic gold with zero PII.
    private static func keyPath(from error: DecodingError) -> String {
        let context: DecodingError.Context?
        switch error {
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx),
             .keyNotFound(_, let ctx), .dataCorrupted(let ctx):
            context = ctx
        @unknown default:
            context = nil
        }
        guard let context, !context.codingPath.isEmpty else { return "<root>" }
        return context.codingPath.map(\.stringValue).joined(separator: ".")
    }
}
