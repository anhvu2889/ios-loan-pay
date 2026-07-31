import Foundation
import LoanPayDomain

/// Derives a full repayment book from a loan's summary numbers.
///
/// WHY synthesis instead of a per-loan fixture file: the mock's list JSON is
/// the single source of truth; detail data derived deterministically from it
/// can never drift out of sync with the list (a classic mock-data bug where
/// the row says "overdue" and the detail says "paid").
enum MockLoanDetailSynthesizer {
    /// Fallback anchor for schedules with no upcoming due date (paid-off
    /// loans); fixed so synthesized output is reproducible run to run.
    private static let fallbackAnchor = Date(timeIntervalSince1970: 1_753_833_600) // 2025-07-30T00:00:00Z

    static func detail(for loan: Loan) -> LoanDetail {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let principal = loan.principal.amount
        let monthly = loan.monthlyInstallment.amount
        let termMonths = max(1, decimalDivideToInt(principal, by: monthly))
        let paidAmount = principal - loan.outstandingBalance.amount
        let paidCount = min(termMonths, max(0, decimalDivideToInt(paidAmount, by: monthly)))

        // The next unpaid installment is anchored to the loan's next due
        // date; everything else is spaced in whole months around it.
        let anchor = loan.nextInstallmentDue ?? fallbackAnchor
        let startDate = calendar.date(byAdding: .month, value: -paidCount, to: anchor) ?? anchor

        let installments = (1...termMonths).map { number -> Installment in
            let offsetFromAnchor = number - (paidCount + 1)
            let dueDate = calendar.date(byAdding: .month, value: offsetFromAnchor, to: anchor) ?? anchor
            let status: Installment.Status
            if number <= paidCount {
                status = .paid
            } else if number == paidCount + 1 {
                status = loan.status == .overdue ? .overdue : .due
            } else {
                status = .upcoming
            }
            return Installment(
                number: number,
                dueDate: dueDate,
                amount: loan.monthlyInstallment,
                status: status
            )
        }

        let balanceHistory = (0...paidCount).map { paid -> BalancePoint in
            let date = calendar.date(byAdding: .month, value: paid, to: startDate) ?? startDate
            let balance = principal - (monthly * Decimal(paid))
            return BalancePoint(
                date: date,
                balance: Money(amount: balance, currencyCode: loan.principal.currencyCode)
            )
        }

        return LoanDetail(
            loan: loan,
            startDate: startDate,
            installments: installments,
            balanceHistory: balanceHistory
        )
    }

    // LANG: Decimal division goes through NSDecimalNumber because Decimal's
    // `/` rounds with banker's behavior we don't control per-call; for
    // deriving integer counts we truncate explicitly (down = floor for the
    // non-negative values used here).
    private static func decimalDivideToInt(_ value: Decimal, by divisor: Decimal) -> Int {
        guard divisor != 0 else { return 0 }
        let result = (value as NSDecimalNumber)
            .dividing(by: divisor as NSDecimalNumber)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .down,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
        return result.intValue
    }
}
