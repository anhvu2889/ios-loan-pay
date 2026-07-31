import SwiftUI
import Charts
import LoanPayDomain

/// The repayment book as a bar chart: one bar per installment, colored by
/// status, with a rule marking today.
struct RepaymentProgressChart: View {
    let installments: [Installment]
    let today: Date

    var body: some View {
        Chart {
            ForEach(installments) { installment in
                BarMark(
                    // WHY month unit on the x axis: due dates are monthly;
                    // a date axis (rather than installment number) is what
                    // lets "today" be drawn as a rule in the same space.
                    x: .value("Due", installment.dueDate, unit: .month),
                    y: .value("Amount", installment.amount.amount.chartValue)
                )
                .foregroundStyle(by: .value("Status", statusLabel(installment.status)))
                .cornerRadius(3)
            }

            RuleMark(x: .value("Today", today))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        // Status colors REINFORCE the legend, they don't replace it — the
        // legend ships with the chart, and the a11y summary speaks counts.
        .chartForegroundStyleScale([
            "Paid": Color.green,
            "Due": Color.blue,
            "Overdue": Color.red,
            "Upcoming": Color.gray.opacity(0.45),
        ])
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 180)
        // WHY a composed summary instead of per-bar labels: VoiceOver users
        // need the shape of the answer ("5 of 12 paid"), not 12 numeric
        // stops. Audio Graphs would be the next step; a sentence is the
        // floor every chart must meet.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func statusLabel(_ status: Installment.Status) -> String {
        switch status {
        case .paid: "Paid"
        case .due: "Due"
        case .overdue: "Overdue"
        case .upcoming: "Upcoming"
        }
    }

    private var accessibilitySummary: String {
        let paid = installments.count(where: { $0.status == .paid })
        let overdue = installments.count(where: { $0.status == .overdue })
        var summary = "Repayment progress: \(paid) of \(installments.count) installments paid"
        if overdue > 0 {
            summary += ", \(overdue) overdue"
        }
        if let next = installments.first(where: { $0.status == .due }) {
            summary += ", next installment of \(next.amount.spokenDescription()) "
                + "due \(next.dueDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return summary
    }
}

extension Decimal {
    // FINTECH: Double is banned for money MATH; this display-only bridge
    // exists because Swift Charts plots on BinaryFloatingPoint. The value
    // drawn as pixels may round in the 15th decimal place; the value in
    // every label and calculation remains the exact Decimal.
    var chartValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
