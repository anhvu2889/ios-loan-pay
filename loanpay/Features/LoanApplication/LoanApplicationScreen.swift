import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

struct LoanApplicationScreen: View {
    @State private var viewModel: LoanApplicationViewModel
    let onFinished: () -> Void

    private enum Field {
        case name, income
    }

    @FocusState private var focusedField: Field?
    @State private var isConfirmingSubmit = false

    init(viewModel: LoanApplicationViewModel, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if case .submitted(let receipt) = viewModel.submission {
                ApplicationSubmittedView(receipt: receipt, onDone: onFinished)
            } else {
                form
            }
        }
        .navigationTitle("Apply for a Loan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCatalog()
        }
    }

    private var form: some View {
        Form {
            Section("About you") {
                TextField("Full name", text: $viewModel.fullName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    // Submit advances to the next field — forms should ride
                    // the keyboard's return key, not force taps.
                    .onSubmit { focusedField = .income }
                fieldError(viewModel.nameError)

                TextField("Monthly income (USD)", text: $viewModel.monthlyIncomeText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .income)
                fieldError(viewModel.incomeError)
            }

            Section("Device") {
                Picker("Device", selection: $viewModel.selectedDevice) {
                    ForEach(viewModel.deviceCatalog, id: \.self) { device in
                        Text(device).tag(Optional(device))
                    }
                }
            }

            Section {
                DatePicker(
                    "First installment",
                    selection: $viewModel.preferredStartDate,
                    // The range makes invalid dates unpickable — validation
                    // by construction beats validation by error message.
                    in: viewModel.startDateRange,
                    displayedComponents: .date
                )
            } footer: {
                Text("Your first installment can start between tomorrow and 30 days from now.")
            }

            Section {
                Toggle("I agree to the loan terms", isOn: $viewModel.termsAccepted)
            } footer: {
                Text("The financed device remains collateral until the loan is fully repaid.")
            }

            if case .failed(let error) = viewModel.submission {
                Section {
                    Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Submit Application") {
                    isConfirmingSubmit = true
                }
                .primaryButton(isLoading: viewModel.submission == .submitting)
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier(AccessibilityID.applicationSubmitButton)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        // WHY a confirmationDialog: submitting starts a credit check — an
        // outward-facing, non-undoable step. One deliberate tap of friction
        // is the cheapest form of consent.
        .confirmationDialog(
            "Submit this application?",
            isPresented: $isConfirmingSubmit,
            titleVisibility: .visible
        ) {
            Button("Submit") {
                Task { await viewModel.submit() }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("We'll run an eligibility check for \(viewModel.selectedDevice ?? "your device").")
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
        }
    }
}
