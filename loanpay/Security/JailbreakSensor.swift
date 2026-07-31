import Foundation
import LoanPayDomain

/// Best-effort device-integrity check.
///
/// FINTECH — DETECT AND SIGNAL, never hard-block, because:
///  1. Every client-side check here is bypassable by the same tools that
///     jailbreak the phone; a hard block only inconveniences honest users
///     of tinkered devices while attackers hook past it in minutes.
///  2. The signal still has real value SERVER-SIDE: a risk engine that
///     sees "jailbroken device + new payee + max amount" can step up
///     verification. The wall belongs where the attacker can't patch it.
///  3. Blocking creates support load in exactly the markets this app
///     serves, where secondhand and vendor-modified devices are common.
struct JailbreakSensor {
    /// Paths that exist on common jailbreaks and never on stock iOS.
    private static let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt",
    ]

    /// Returns signal types found; empty means "nothing observed" (which
    /// is NOT a clean bill — see above).
    func detectSignals() -> [String] {
        var signals: [String] = []

        if Self.suspiciousPaths.contains(where: FileManager.default.fileExists(atPath:)) {
            signals.append("jailbreak_path_present")
        }

        // The sandbox write probe: a stock app cannot write outside its
        // container. Success here means the sandbox is not enforcing.
        let probePath = "/private/loanpay_probe_\(UUID().uuidString).txt"
        if (try? "probe".write(toFile: probePath, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probePath)
            signals.append("sandbox_escape_write")
        }

        #if targetEnvironment(simulator)
        // The simulator has no sandbox in the device sense; suppress noise
        // so development analytics stay meaningful.
        signals.removeAll()
        #endif

        return signals
    }
}
