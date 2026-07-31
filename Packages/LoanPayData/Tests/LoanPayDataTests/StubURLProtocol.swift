import Foundation

/// Intercepts URLSession traffic inside tests.
///
/// ARCH: this class lives in the TEST TARGET on purpose — it must never
/// exist in a shipping binary (a registered URLProtocol is a man-in-the-
/// middle by design). The release-audit step greps the app product for
/// this symbol to prove it stayed here.
final class StubURLProtocol: URLProtocol {
    /// The test's scripted server: request in, (response, body) out.
    /// `nonisolated(unsafe)` is honest about the discipline: the suites
    /// that touch it run `.serialized`, so access never races.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    // swiftlint:disable static_over_final_class
    // URLProtocol declares these as `class func`; an override must match —
    // `static` here would not compile.
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension StubURLProtocol {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func httpResponse(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
