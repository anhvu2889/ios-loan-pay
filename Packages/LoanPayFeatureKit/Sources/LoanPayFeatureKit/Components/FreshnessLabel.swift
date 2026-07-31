import SwiftUI

/// "Updated 12 minutes ago" — shown ONLY for cache-served content.
///
/// WHY nothing when fresh: labeling live data "updated just now" trains
/// users to ignore the label; its entire job is to flag staleness.
public struct FreshnessLabel: View {
    private let fetchedAt: Date
    private let isFromCache: Bool

    public init(fetchedAt: Date, isFromCache: Bool) {
        self.fetchedAt = fetchedAt
        self.isFromCache = isFromCache
    }

    public var body: some View {
        if isFromCache {
            // MODERN: Text with a relative format style live-updates as
            // time passes ("2m ago" becomes "3m ago") with no timer code —
            // the pre-iOS-15 version was a Timer publisher re-rendering a
            // RelativeDateTimeFormatter string.
            Label {
                Text("Updated \(fetchedAt, format: .relative(presentation: .named))")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Showing saved data, updated \(fetchedAt.formatted(.relative(presentation: .named)))")
        }
    }
}

#Preview("Stale") {
    FreshnessLabel(fetchedAt: Date().addingTimeInterval(-780), isFromCache: true)
        .padding()
}

#Preview("Fresh renders nothing") {
    FreshnessLabel(fetchedAt: Date(), isFromCache: false)
        .padding()
}
