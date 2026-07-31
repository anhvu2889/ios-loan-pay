import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// The portfolio totals card above the list.
struct PortfolioSummaryHeader: View {
    let summary: LoanListViewModel.SummaryState

    var body: some View {
        switch summary {
        case .idle:
            EmptyView()

        case .loading:
            card(total: Money(amount: 888.88, currencyCode: "USD"), overdueCount: 0, incomplete: false)
                // Skeleton over REAL layout: redaction keeps the final
                // geometry, so content doesn't jump when numbers arrive.
                .redacted(reason: .placeholder)

        case .loaded(let summary):
            card(
                total: summary.totalOutstanding,
                overdueCount: summary.overdueLoanCount,
                incomplete: !summary.isComplete
            )

        case .failed:
            // WHY quiet failure: the header is garnish; the list below is
            // the meal. A failed aggregate should never block the screen.
            EmptyView()
        }
    }

    private func card(total: Money, overdueCount: Int, incomplete: Bool) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total outstanding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AmountText(total)
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    if overdueCount > 0 {
                        Label("\(overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    if incomplete {
                        // FINTECH: a partial total says so. Quietly showing
                        // a smaller number than the truth is the one
                        // direction a lender must never round.
                        Label("Some loans not included", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(total: total, overdueCount: overdueCount, incomplete: incomplete))
        .accessibilityIdentifier(AccessibilityID.portfolioSummaryHeader)
    }

    private func accessibilitySummary(total: Money, overdueCount: Int, incomplete: Bool) -> String {
        var text = "Total outstanding \(total.spokenDescription())"
        if overdueCount > 0 { text += ", \(overdueCount) loans overdue" }
        if incomplete { text += ", some loans not included" }
        return text
    }
}

#Preview("Loaded") {
    PortfolioSummaryHeader(summary: .loaded(PortfolioSummary(
        totalOutstanding: Money(amount: 1043, currencyCode: "USD"),
        overdueLoanCount: 3,
        includedLoanIDs: [],
        failedLoanIDs: []
    )))
    .padding()
}

#Preview("Partial") {
    PortfolioSummaryHeader(summary: .loaded(PortfolioSummary(
        totalOutstanding: Money(amount: 900, currencyCode: "USD"),
        overdueLoanCount: 1,
        includedLoanIDs: [],
        failedLoanIDs: [LoanID("x")]
    )))
    .padding()
}

#Preview("Loading skeleton") {
    PortfolioSummaryHeader(summary: .loading)
        .padding()
}
