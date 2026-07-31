import Foundation
import LoanPayDomain

/// Logger for previews: swallows everything. Previews should render, not
/// spray the console of whoever opened the canvas.
public struct PreviewLogger: AppLogger {
    public init() {}

    public func log(_ level: LogLevel, category: LogCategory, _ message: @autoclosure () -> String) {}
}
