import Foundation
import Testing
import LoanPayDomain
@testable import LoanPayData

// Pure evaluation only — the tests that need StubURLProtocol live in
// URLSessionAPIClientTests (ONE suite may own that global handler; two
// .serialized suites still run in parallel with each other).
@Suite struct CertificatePinningTests {
    @Test func evaluationMatrix() {
        let pinning = CertificatePinning(
            pinsByHost: ["api.loanpay.example": ["primaryHash", "backupHash"]],
            allowsLocalhostBypass: true
        )
        #expect(pinning.evaluate(host: "api.loanpay.example", spkiHashes: ["primaryHash"]) == .accepted)
        // Backup pin keeps old builds alive mid-rotation.
        #expect(pinning.evaluate(host: "api.loanpay.example", spkiHashes: ["other", "backupHash"]) == .accepted)
        #expect(pinning.evaluate(host: "api.loanpay.example", spkiHashes: ["attacker"]) == .rejected)
        #expect(pinning.evaluate(host: "api.loanpay.example", spkiHashes: []) == .rejected)
        #expect(pinning.evaluate(host: "cdn.elsewhere.example", spkiHashes: ["whatever"]) == .hostNotPinned)
        #expect(pinning.evaluate(host: "localhost", spkiHashes: []) == .bypassedForLocalhost)
    }

    @Test func localhostBypassIsOffByDefault() {
        let pinning = CertificatePinning(pinsByHost: [:])
        // Without the explicit (DEBUG-composed) opt-in, localhost gets the
        // same treatment as any unpinned host — no special door.
        #expect(pinning.evaluate(host: "localhost", spkiHashes: []) == .hostNotPinned)
    }

}
