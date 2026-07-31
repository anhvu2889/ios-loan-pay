import Foundation
import Observation
import LoanPayDomain

@Observable
@MainActor
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case loggingIn
        case failed(String)
    }

    var username = ""
    var password = ""
    private(set) var state: State = .idle

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && state != .loggingIn
    }

    private let authService: any AuthService
    private let onSuccess: (String) -> Void

    init(authService: any AuthService, onSuccess: @escaping (String) -> Void) {
        self.authService = authService
        // LANG: the success hand-off is an @escaping closure, not a
        // reference to the flow coordinator — the ViewModel cannot navigate,
        // cannot see other screens, and tests assert on a captured value.
        self.onSuccess = onSuccess
    }

    func submit() async {
        guard canSubmit else { return }
        state = .loggingIn
        do {
            let token = try await authService.login(username: username, password: password)
            state = .idle
            onSuccess(token)
        } catch is CancellationError {
            state = .idle
        } catch let error as DomainError {
            state = .failed(error == .unauthorized
                ? "That username and password don't match."
                : error.userMessage)
        } catch {
            state = .failed(DomainError.unknown.userMessage)
        }
    }
}
