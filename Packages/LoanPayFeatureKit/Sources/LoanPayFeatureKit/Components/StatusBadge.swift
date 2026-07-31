import SwiftUI
import LoanPayDomain

/// Loan status rendered as icon + text + tint.
///
/// WHY icon+text and never color alone: roughly 1 in 12 men cannot reliably
/// distinguish the red/green this badge leans on, and grayscale screenshots
/// (support tickets!) drop color entirely. Color here is reinforcement,
/// not information.
public struct StatusBadge: View {
    private let status: LoanStatus

    public init(_ status: LoanStatus) {
        self.status = status
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .accessibilityLabel("Status: \(title)")
    }

    // ARCH: presentation metadata for a domain enum lives HERE, not on
    // LoanStatus — Domain must stay renderable-agnostic, and two screens
    // wanting different wordings should not fight over a domain property.
    private var title: String {
        switch status {
        case .active: "Active"
        case .overdue: "Overdue"
        case .paidOff: "Paid off"
        case .unknown: "Status unavailable"
        }
    }

    private var systemImage: String {
        switch status {
        case .active: "checkmark.circle"
        case .overdue: "exclamationmark.triangle.fill"
        case .paidOff: "checkmark.seal.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .active: .green
        case .overdue: .red
        case .paidOff: .blue
        case .unknown: .secondary
        }
    }
}

#Preview("All statuses") {
    VStack(spacing: 12) {
        StatusBadge(.active)
        StatusBadge(.overdue)
        StatusBadge(.paidOff)
        StatusBadge(.unknown)
    }
    .padding()
}

#Preview("Large type") {
    StatusBadge(.overdue)
        .environment(\.dynamicTypeSize, .accessibility3)
        .padding()
}
