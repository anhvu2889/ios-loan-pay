import Foundation

/// The credential-exchange seam: credentials in, session token out.
protocol AuthService: Sendable {
    func login(username: String, password: String) async throws -> String
}
