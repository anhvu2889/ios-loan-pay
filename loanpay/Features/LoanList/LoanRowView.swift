import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

/// One loan in the list. Receives VALUES and closures only — no ViewModel —
/// so it previews with literals and can move packages freely.
struct LoanRowView: View {
    let loan: Loan
    let onSelect: () -> Void
    let onRequestCallback: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loan.deviceModel)
                        .font(.headline)
                    if let due = loan.nextInstallmentDue {
                        Text("Next payment \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    AmountText(loan.outstandingBalance)
                        .font(.body.weight(.semibold))
                    StatusBadge(loan.status)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.loanRow(loan.id))
        // WHY combine: without it VoiceOver walks four separate fragments
        // per row ("Galaxy A15" … swipe … "$140.00" … swipe …). One element
        // with a composed sentence makes a row one swipe, and the amount is
        // spoken as currency words, never digit-by-digit.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onRequestCallback()
            } label: {
                Label("Request Callback", systemImage: "phone.arrow.up.right")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("View Details", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [loan.deviceModel]
        switch loan.status {
        case .active: parts.append("active loan")
        case .overdue: parts.append("overdue loan")
        case .paidOff: parts.append("paid off")
        case .unknown: parts.append("status unavailable")
        }
        parts.append("balance \(loan.outstandingBalance.spokenDescription())")
        if let due = loan.nextInstallmentDue {
            parts.append("next payment \(due.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Rows") {
    List {
        LoanRowView(loan: PreviewFixtures.activeLoan, onSelect: {}, onRequestCallback: {})
        LoanRowView(loan: PreviewFixtures.overdueLoan, onSelect: {}, onRequestCallback: {})
        LoanRowView(loan: PreviewFixtures.paidOffLoan, onSelect: {}, onRequestCallback: {})
    }
    .listStyle(.plain)
}
