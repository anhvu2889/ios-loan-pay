import Foundation
import LoanPayDomain

/// The reference HTTP client: auth, correlation, idempotency and status
/// gating in ONE place, so no repository ever hand-rolls a URLRequest.
public struct URLSessionAPIClient: Sendable {
    /// Async because the token lives in an actor (SessionStore); the client
    /// must not know which one.
    public typealias TokenProvider = @Sendable () async -> String?

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProvider
    private let logger: any AppLogger

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider,
        logger: any AppLogger
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.logger = logger
    }

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(method: "GET", path: path, query: query, body: nil, idempotencyKey: nil)
    }

    public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        idempotencyKey: IdempotencyKey? = nil
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return try await send(
            method: "POST",
            path: path,
            query: [],
            body: try encoder.encode(body),
            idempotencyKey: idempotencyKey
        )
    }

    private func send<Response: Decodable & Sendable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        idempotencyKey: IdempotencyKey?
    ) async throws -> Response {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        // FINTECH: the Bearer token rides in a header assembled here and
        // nowhere else — no repository can forget auth, and no URL ever
        // carries a token (URLs end up in proxy logs and crash reports).
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // WHY per-request correlation ids: when a borrower disputes a
        // payment, support greps ONE id across app logs and every backend
        // hop. Minted per request, never reused, safe to log (it is
        // meaningless without the server's side).
        let correlationID = UUID().uuidString
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-ID")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // FINTECH: the Idempotency-Key header is set from the REQUEST's
        // key — the client never mints one. Minting here would silently
        // give each HTTP retry a fresh key, destroying the exactly-once
        // guarantee the payment flow builds.
        if let idempotencyKey {
            request.setValue(idempotencyKey.value, forHTTPHeaderField: "Idempotency-Key")
        }

        logger.log(.debug, category: .network, "\(method) \(path)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // WHY status gating BEFORE decode: an error body decoded as a
        // success DTO produces a DecodingError that lies about the problem.
        // The status is the truth; decode only after it says 2xx.
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError(statusCode: http.statusCode)
        }

        return try MockFixtures.makeDecoder().decode(Response.self, from: data)
    }
}
