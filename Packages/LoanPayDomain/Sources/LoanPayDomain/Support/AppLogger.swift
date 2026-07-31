import Foundation

public enum LogCategory: String, Sendable {
    case network
    case payment
    case outbox
    case ui
}

public enum LogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

// ARCH: a protocol over os.Logger (the concrete adapter lives in the app
// layer) so Domain and Data code can log without importing OSLog, and tests
// can assert on log output with an in-memory implementation.
//
// FINTECH: the no-PII rule lives at this seam — messages must never contain
// amounts, names, tokens or full loan payloads. Log the *shape* of events
// ("payment failed: timeout"), never their contents. os_log's privacy
// redaction is a backstop, not a license.
public protocol AppLogger: Sendable {
    // LANG: @autoclosure defers building the message string until the logger
    // decides it will actually be emitted — callers write log(.debug, ...)
    // with string interpolation and pay nothing for suppressed levels.
    func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String)
}
