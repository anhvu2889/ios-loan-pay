import Foundation
import LoanPayDomain

/// Development login: any non-empty credentials succeed after a simulated
/// round-trip. The token is random per login — nothing downstream may
/// assume token structure.
struct StubAuthService: AuthService {
    private let sleeper: any Sleeper

    init(sleeper: any Sleeper) {
        self.sleeper = sleeper
    }

    func login(username: String, password: String) async throws -> String {
        try await sleeper.sleep(for: .milliseconds(600))
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            throw DomainError.unauthorized
        }
        return "session-\(UUID().uuidString)"
    }
}
