import Foundation
import Security
import LoanPayDomain

/// URLSession delegate that enforces the pin set during the TLS handshake.
///
/// LANG: `@unchecked Sendable` with an NSLock over `violationCount` —
/// URLSession calls the delegate on its own queue while the client reads
/// the flag from a task; the lock covers both, and nothing else here
/// mutates.
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinning: CertificatePinning
    private let logger: any AppLogger
    private let lock = NSLock()
    private var violationCount = 0

    public init(pinning: CertificatePinning, logger: any AppLogger) {
        self.pinning = pinning
        self.logger = logger
    }

    /// The client checks this after a request fails to distinguish "we
    /// refused the connection" from ordinary cancellation.
    public func consumeViolation() -> Bool {
        lock.withLock {
            guard violationCount > 0 else { return false }
            violationCount -= 1
            return true
        }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        switch pinning.evaluate(host: host, spkiHashes: Self.spkiHashes(from: trust)) {
        case .accepted:
            // Pin matched AND we hand the trust back so the system still
            // runs its full evaluation (expiry, hostname, chain) — pinning
            // NARROWS trust, it must never replace it.
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .hostNotPinned:
            completionHandler(.performDefaultHandling, nil)
        case .bypassedForLocalhost:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .rejected:
            lock.withLock { violationCount += 1 }
            // Host name is infrastructure, not PII — log it; never log the
            // presented key material.
            logger.log(.error, category: .network, "certificate pin mismatch; connection refused")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Test hook: simulating a refused handshake without a live TLS
    /// session. Does exactly what the mismatch branch above does.
    public func recordViolationForTesting() {
        lock.withLock { violationCount += 1 }
    }

    /// SPKI hashes of every certificate in the presented chain.
    private static func spkiHashes(from trust: SecTrust) -> [String] {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return []
        }
        return chain.compactMap { certificate in
            guard let key = SecCertificateCopyKey(certificate),
                  let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
                return nil
            }
            return CertificatePinning.spkiHash(of: keyData)
        }
    }
}
