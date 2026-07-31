import SwiftUI

/// The standard grouped-content surface.
public struct CardContainer<Content: View>: View {
    private let content: Content

    // LANG: @ViewBuilder on the init parameter (not a stored closure) means
    // callers write natural `CardContainer { ... }` syntax and the content
    // is built once, eagerly — no closure retained beyond init.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    /// Card dress for content that already manages its own layout.
    public func cardStyle() -> some View {
        CardContainer { self }
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Outstanding balance").font(.caption).foregroundStyle(.secondary)
                Text("$140.00").font(.title2.bold())
            }
        }
        Text("Plain text, card-dressed").cardStyle()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Dark") {
    Text("Card in dark mode")
        .cardStyle()
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
