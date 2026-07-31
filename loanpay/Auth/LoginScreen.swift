import SwiftUI
import LoanPayFeatureKit

struct LoginScreen: View {
    @Bindable var viewModel: LoginViewModel

    private enum Field {
        case username, password
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("LoanPay")
                    .font(.largeTitle.bold())
                Text("Sign in to manage your device loans")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Username", text: $viewModel.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.submit() } }
                    .textFieldStyle(.roundedBorder)
            }

            if case .failed(let message) = viewModel.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Sign In") {
                Task { await viewModel.submit() }
            }
            .primaryButton(isLoading: viewModel.state == .loggingIn)
            .disabled(!viewModel.canSubmit)

            Spacer()
            Spacer()
        }
        .padding(24)
    }
}
