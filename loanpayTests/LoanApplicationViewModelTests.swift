import Foundation
import Testing
import LoanPayDomain
@testable import loanpay

actor StubApplicationRepository: LoanApplicationRepository {
    var submitResult: Result<ApplicationReceipt, DomainError>
    private(set) var submitted: [LoanApplication] = []

    init(submitResult: Result<ApplicationReceipt, DomainError> = .success(
        ApplicationReceipt(applicationID: "app-1", submittedAt: testDate)
    )) {
        self.submitResult = submitResult
    }

    func fetchDeviceCatalog() async throws -> [String] {
        ["Galaxy A15", "Redmi 13C"]
    }

    func submit(_ application: LoanApplication) async throws -> ApplicationReceipt {
        submitted.append(application)
        return try submitResult.get()
    }
}

@MainActor
@Suite struct LoanApplicationViewModelTests {
    private func makeViewModel(
        repository: StubApplicationRepository = StubApplicationRepository()
    ) async -> LoanApplicationViewModel {
        let viewModel = LoanApplicationViewModel(
            repository: repository,
            now: { testDate }
        )
        await viewModel.loadCatalog()
        return viewModel
    }

    /// A fully valid form, to be broken one field at a time.
    private func fillValid(_ viewModel: LoanApplicationViewModel) {
        viewModel.fullName = "Amina Okafor"
        viewModel.monthlyIncomeText = "250.50"
        viewModel.termsAccepted = true
    }

    // MARK: - Validation matrix

    @Test func validFormCanSubmit() async {
        let viewModel = await makeViewModel()
        fillValid(viewModel)
        #expect(viewModel.canSubmit)
        #expect(viewModel.nameError == nil)
        #expect(viewModel.incomeError == nil)
    }

    @Test func emptyFieldsBlockSubmissionWithoutShowingErrors() async {
        let viewModel = await makeViewModel()
        // Untouched form: disabled, but no red ink.
        #expect(!viewModel.canSubmit)
        #expect(viewModel.nameError == nil)
        #expect(viewModel.incomeError == nil)
    }

    @Test(arguments: [
        ("A", "Enter your full name."),
        ("Amina 4", "Names don't contain digits."),
    ])
    func invalidNamesShowFieldErrors(name: String, expected: String) async {
        let viewModel = await makeViewModel()
        fillValid(viewModel)
        viewModel.fullName = name
        #expect(viewModel.nameError == expected)
        #expect(!viewModel.canSubmit)
    }

    @Test(arguments: [
        "abc",      // not a number
        "25o",      // prefix-parses as 25 without the strict grammar
        "250.505",  // too many decimal places
        "-10",      // negative
    ])
    func malformedIncomeShowsTheFormatError(income: String) async {
        let viewModel = await makeViewModel()
        fillValid(viewModel)
        viewModel.monthlyIncomeText = income
        #expect(viewModel.incomeError == "Enter a valid amount, like 250 or 250.50.")
        #expect(!viewModel.canSubmit)
    }

    @Test func incomeBelowThresholdShowsTheMinimumError() async {
        let viewModel = await makeViewModel()
        fillValid(viewModel)
        viewModel.monthlyIncomeText = "49.99"
        #expect(viewModel.incomeError?.contains("at least") == true)
        #expect(!viewModel.canSubmit)
    }

    @Test func unacceptedTermsBlockSubmission() async {
        let viewModel = await makeViewModel()
        fillValid(viewModel)
        viewModel.termsAccepted = false
        #expect(!viewModel.canSubmit)
        // No field error — the disabled button + toggle state is the UI.
        #expect(viewModel.nameError == nil && viewModel.incomeError == nil)
    }

    @Test func startDateRangeBeginsTomorrowAndEndsAtThirtyDays() async {
        let viewModel = await makeViewModel()
        let calendar = Calendar.current
        #expect(viewModel.startDateRange.lowerBound == calendar.date(byAdding: .day, value: 1, to: testDate))
        #expect(viewModel.startDateRange.upperBound == calendar.date(byAdding: .day, value: 30, to: testDate))
        #expect(viewModel.startDateRange.contains(viewModel.preferredStartDate))
    }

    // MARK: - Submission

    @Test func submitSendsTheParsedApplicationAndLandsInSubmitted() async {
        let repository = StubApplicationRepository()
        let viewModel = await makeViewModel(repository: repository)
        fillValid(viewModel)

        await viewModel.submit()

        guard case .submitted(let receipt) = viewModel.submission else {
            Issue.record("expected submitted, got \(viewModel.submission)")
            return
        }
        #expect(receipt.applicationID == "app-1")

        let sent = await repository.submitted
        #expect(sent.count == 1)
        #expect(sent[0].applicantName == "Amina Okafor")
        #expect(sent[0].monthlyIncome == Money(amount: Decimal(string: "250.50")!, currencyCode: "USD"))
        #expect(sent[0].deviceModel == "Galaxy A15")
        #expect(sent[0].termsAcceptedAt == testDate)
    }

    @Test func invalidFormRefusesToSubmitAtTheViewModelToo() async {
        let repository = StubApplicationRepository()
        let viewModel = await makeViewModel(repository: repository)
        // Belt-and-suspenders: even if the UI forgot to disable the button,
        // the ViewModel checks again.
        await viewModel.submit()
        await #expect(repository.submitted.isEmpty)
        #expect(viewModel.submission == .idle)
    }

    @Test func failedSubmissionSurfacesARetryableError() async {
        let repository = StubApplicationRepository(submitResult: .failure(.timeout))
        let viewModel = await makeViewModel(repository: repository)
        fillValid(viewModel)

        await viewModel.submit()

        #expect(viewModel.submission == .failed(.timeout))

        // The form is still intact for a retry.
        #expect(viewModel.canSubmit)
    }
}
