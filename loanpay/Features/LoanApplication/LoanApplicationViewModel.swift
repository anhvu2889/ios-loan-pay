import Foundation
import Observation
import LoanPayDomain

@Observable
@MainActor
final class LoanApplicationViewModel {
    enum SubmissionState: Equatable {
        case idle
        case submitting
        case failed(DomainError)
        case submitted(ApplicationReceipt)
    }

    // Form fields — bound directly by the Form; validation reacts to every
    // keystroke because it is pure computation over these values.
    var fullName = ""
    var monthlyIncomeText = ""
    var selectedDevice: String?
    var preferredStartDate: Date
    var termsAccepted = false

    private(set) var submission: SubmissionState = .idle
    private(set) var deviceCatalog: [String] = []

    /// Submission range: tomorrow through +30 days. The DatePicker gets
    /// this range so invalid dates are unpickable rather than validated
    /// after the fact.
    let startDateRange: ClosedRange<Date>

    private let repository: any LoanApplicationRepository
    private let now: () -> Date

    // LANG: `now` is an injected closure, not Date() calls sprinkled
    // through the logic — validation involving "tomorrow" is only testable
    // if the test controls what "now" means.
    init(repository: any LoanApplicationRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
        let today = now()
        let start = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let end = Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today
        self.startDateRange = start...end
        self.preferredStartDate = start
    }

    func loadCatalog() async {
        deviceCatalog = (try? await repository.fetchDeviceCatalog()) ?? []
        if selectedDevice == nil {
            selectedDevice = deviceCatalog.first
        }
    }

    // MARK: - Live validation

    // WHY errors are nil for EMPTY fields: an untouched form screaming red
    // teaches users to ignore red. Empty means "not done yet" (submit
    // stays disabled); an error appears only once there is input to judge.
    var nameError: String? {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count >= 2 else { return "Enter your full name." }
        guard trimmed.rangeOfCharacter(from: CharacterSet.decimalDigits) == nil else {
            return "Names don't contain digits."
        }
        return nil
    }

    var incomeError: String? {
        guard !monthlyIncomeText.isEmpty else { return nil }
        guard let value = parsedIncome else {
            return "Enter a valid amount, like 250 or 250.50."
        }
        guard value >= 50 else {
            return "Applications need a monthly income of at least $50."
        }
        return nil
    }

    var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && nameError == nil
            && parsedIncome != nil
            && incomeError == nil
            && selectedDevice != nil
            && termsAccepted
            && submission != .submitting
    }

    private var parsedIncome: Decimal? {
        let text = monthlyIncomeText.trimmingCharacters(in: .whitespaces)
        // Same strict-grammar rule as the wire: Decimal(string:) is a
        // prefix parser and would accept "25o" as 25.
        guard text.wholeMatch(of: /[0-9]+(?:\.[0-9]{1,2})?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Submission

    func submit() async {
        guard canSubmit, let device = selectedDevice, let income = parsedIncome else { return }
        submission = .submitting
        let application = LoanApplication(
            applicantName: fullName.trimmingCharacters(in: .whitespaces),
            monthlyIncome: Money(amount: income, currencyCode: "USD"),
            deviceModel: device,
            preferredStartDate: preferredStartDate,
            termsAcceptedAt: now()
        )
        do {
            submission = .submitted(try await repository.submit(application))
        } catch is CancellationError {
            submission = .idle
        } catch let error as DomainError {
            submission = .failed(error)
        } catch {
            submission = .failed(.unknown)
        }
    }

    func dismissError() {
        if case .failed = submission {
            submission = .idle
        }
    }
}
