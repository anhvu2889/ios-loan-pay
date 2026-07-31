import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

struct ScriptedAuthService: AuthService {
    var result: Result<String, DomainError>

    func login(username: String, password: String) async throws -> String {
        try result.get()
    }
}

@MainActor
@Suite struct LoginViewModelTests {
    @Test func successHandsTheTokenToTheFlow() async {
        var received: String?
        let viewModel = LoginViewModel(
            authService: ScriptedAuthService(result: .success("token-1")),
            onSuccess: { received = $0 }
        )
        viewModel.username = "amina"
        viewModel.password = "secret"

        await viewModel.submit()

        #expect(received == "token-1")
        #expect(viewModel.state == .idle)
    }

    @Test func rejectionShowsACredentialMessageNotAServerOne() async {
        let viewModel = LoginViewModel(
            authService: ScriptedAuthService(result: .failure(.unauthorized)),
            onSuccess: { _ in }
        )
        viewModel.username = "amina"
        viewModel.password = "wrong"

        await viewModel.submit()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("expected failed state")
            return
        }
        #expect(message.contains("username and password"))
    }

    @Test func emptyFieldsCannotSubmit() async {
        var called = false
        let viewModel = LoginViewModel(
            authService: ScriptedAuthService(result: .success("t")),
            onSuccess: { _ in called = true }
        )

        await viewModel.submit()

        #expect(!called)
        #expect(!viewModel.canSubmit)
    }
}
