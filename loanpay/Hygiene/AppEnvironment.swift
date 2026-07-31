import Foundation

/// Which backend the app talks to.
enum AppEnvironment: String, CaseIterable {
    /// The in-process mock repositories — the runtime DEFAULT. No network,
    /// deterministic data, failure injection via the debug menu.
    case mockInProcess
    /// The json-server instance from Scripts/mock-server, over real
    /// URLSession networking.
    case remoteLocalhost

    static let defaultsKey = "loanpay-environment"

    /// Resolution order: launch argument / debug-menu override (both land
    /// in UserDefaults — `-loanpay-environment remoteLocalhost` on the
    /// command line populates the argument domain automatically), then the
    /// mock default.
    ///
    /// WHY DEBUG-only: a shipping build must have exactly one environment.
    /// An App Store binary that can be pointed at "localhost" is a binary
    /// that can be pointed at an attacker's proxy.
    static func current() -> AppEnvironment {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let selected = AppEnvironment(rawValue: raw) {
            return selected
        }
        #endif
        return .mockInProcess
    }
}
