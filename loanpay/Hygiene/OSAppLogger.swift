import Foundation
import OSLog
import LoanPayDomain

/// The production `AppLogger`: a thin adapter over `os.Logger`, one
/// underlying logger per category so Console.app can filter by subsystem +
/// category.
///
/// ARCH: this adapter is the only file in the app that imports OSLog for
/// logging. Domain/Data code logs through the `AppLogger` protocol and
/// stays framework-free; tests substitute an in-memory recorder.
struct OSAppLogger: AppLogger {
    private let loggers: [LogCategory: Logger]

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "loanpay") {
        var loggers: [LogCategory: Logger] = [:]
        for category in [LogCategory.network, .payment, .outbox, .ui] {
            loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        self.loggers = loggers
    }

    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {
        guard let logger = loggers[category] else { return }
        // FINTECH: `\(text, privacy: .public)` looks backwards for a no-PII
        // rule, but the real rule is enforced UPSTREAM: messages must never
        // contain amounts, names or tokens in the first place (see
        // AppLogger's contract). Marking them public keeps diagnostics
        // readable in sysdiagnoses; marking them private would only redact
        // messages that were already safe — or hide a leak instead of
        // preventing it.
        let text = message()
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
    }
}
