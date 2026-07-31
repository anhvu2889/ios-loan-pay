import Foundation
import CryptoKit

/// The pin set and the pure decision logic for certificate pinning.
///
/// FINTECH: we pin SPKI PUBLIC-KEY hashes, not leaf certificates. Leaf
/// certs rotate every 90 days with automated issuance — pinning them is a
/// scheduled outage. The public key survives reissuance, so pins only
/// change when the KEY changes, which is an event we control.
///
/// FINTECH — the rotation story (pinning without one IS an outage plan):
///   1. `hashes` always contains the ACTIVE key's pin AND a BACKUP pin for
///      a key generated and stored offline.
///   2. Rotation: deploy the backup key server-side (already trusted by
///      every shipped build), then ship an app update whose pin set is
///      {new-active, new-backup}.
///   3. Old builds keep working through step 2 because the backup pin was
///      in their set all along. No flag day, no bricked clients.
public struct CertificatePinning: Sendable {
    public enum Decision: Equatable, Sendable {
        case accepted
        case rejected
        /// Host isn't pinned — fall through to standard system trust.
        case hostNotPinned
        case bypassedForLocalhost
    }

    /// host → base64(SHA-256(SPKI)) pins. Always ≥ 2 entries per host
    /// (active + backup).
    private let pinsByHost: [String: Set<String>]
    private let allowsLocalhostBypass: Bool

    public init(pinsByHost: [String: Set<String>], allowsLocalhostBypass: Bool = false) {
        self.pinsByHost = pinsByHost
        self.allowsLocalhostBypass = allowsLocalhostBypass
    }

    /// Reference pin set for the production API host. The values are
    /// placeholders with the right SHAPE — a real deployment generates them
    /// from its keys: openssl x509 -pubkey | openssl pkey -pubin
    /// -outform der | openssl dgst -sha256 -binary | base64
    public static func production(allowsLocalhostBypass: Bool) -> CertificatePinning {
        CertificatePinning(
            pinsByHost: [
                "api.loanpay.example": [
                    "PRIMARYpinPlaceholder000000000000000000000004Q=",
                    "BACKUPpinPlaceholder0000000000000000000000005Q=",
                ]
            ],
            allowsLocalhostBypass: allowsLocalhostBypass
        )
    }

    /// Pure and synchronous — THE testable core. The URLSession delegate's
    /// only job is extracting SPKI data from the trust chain and calling
    /// this.
    public func evaluate(host: String, spkiHashes: [String]) -> Decision {
        // WHY the bypass is host-scoped AND compile-time gated by the
        // caller: the local json-server has no certificate at all. The
        // bypass must never widen beyond loopback.
        if allowsLocalhostBypass, host == "localhost" || host == "127.0.0.1" {
            return .bypassedForLocalhost
        }
        guard let pins = pinsByHost[host] else {
            return .hostNotPinned
        }
        // ANY key in the presented chain matching ANY pin passes — this is
        // what lets the backup key take over mid-rotation.
        return spkiHashes.contains(where: pins.contains) ? .accepted : .rejected
    }

    public static func spkiHash(of keyData: Data) -> String {
        Data(SHA256.hash(data: keyData)).base64EncodedString()
    }
}
