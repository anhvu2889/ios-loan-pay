import SwiftUI

/// Outbox status chip: how many queued writes await delivery, and whether
/// any have given up and need a manual nudge.
public struct SyncBadge: View {
    private let pendingCount: Int
    private let hasFailures: Bool
    private let onRetry: () -> Void

    public init(pendingCount: Int, hasFailures: Bool, onRetry: @escaping () -> Void) {
        self.pendingCount = pendingCount
        self.hasFailures = hasFailures
        self.onRetry = onRetry
    }

    public var body: some View {
        if pendingCount > 0 || hasFailures {
            Button(action: onRetry) {
                Label {
                    Text("\(pendingCount)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: hasFailures
                        ? "exclamationmark.arrow.triangle.2.circlepath"
                        : "arrow.triangle.2.circlepath")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((hasFailures ? Color.orange : Color.secondary).opacity(0.15), in: Capsule())
                .foregroundStyle(hasFailures ? Color.orange : Color.secondary)
            }
            .accessibilityIdentifier(AccessibilityID.syncBadge)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var accessibilityDescription: String {
        hasFailures
            ? "\(pendingCount) requests waiting to send, some failed. Double tap to retry."
            : "\(pendingCount) requests waiting to send."
    }
}

#Preview("Pending") {
    SyncBadge(pendingCount: 2, hasFailures: false, onRetry: {})
        .padding()
}

#Preview("Failed") {
    SyncBadge(pendingCount: 1, hasFailures: true, onRetry: {})
        .padding()
}

#Preview("Empty renders nothing") {
    SyncBadge(pendingCount: 0, hasFailures: false, onRetry: {})
        .padding()
}
