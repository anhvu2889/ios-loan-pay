import SwiftUI
import Charts
import LoanPayDomain

/// Outstanding balance over the life of the loan, as a simple line.
struct BalanceHistoryChart: View {
    let history: [BalancePoint]

    var body: some View {
        Chart(history, id: \.date) { point in
            LineMark(
                x: .value("Date", point.date, unit: .month),
                y: .value("Balance", point.balance.amount.chartValue)
            )
            .interpolationMethod(.monotone)
            AreaMark(
                x: .value("Date", point.date, unit: .month),
                y: .value("Balance", point.balance.amount.chartValue)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [Color.accentColor.opacity(0.25), .clear],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = history.first, let last = history.last else {
            return "Balance history unavailable"
        }
        return "Balance decreased from \(first.balance.spokenDescription()) to \(last.balance.spokenDescription()) over \(history.count) months"
    }
}
