import SwiftUI

/// Generic renderer for the four display shapes every loading screen
/// shares. Screens map their own state enum onto `DisplayState` and provide
/// only the loaded content; the empty/error/loading furniture is uniform
/// app-wide because it lives here once.
public struct StateContainer<Content: View>: View {
    // ARCH: this is a *display* state, deliberately poorer than any
    // ViewModel's state enum — no associated data beyond what rendering
    // needs, no domain types. ViewModels translate rich state down to it;
    // the component stays reusable because it knows nothing.
    public enum DisplayState: Equatable {
        case loading
        case content
        case empty(title: String, message: String)
        case error(message: String, isRetryable: Bool)
    }

    private let state: DisplayState
    private let onRetry: (() -> Void)?
    private let content: Content

    // ARCH: values and closures in, never a ViewModel — the component must
    // be previewable with literals and reusable by every feature package
    // without importing any of them.
    public init(
        state: DisplayState,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.onRetry = onRetry
        self.content = content()
    }

    public var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .content:
            content

        case .empty(let title, let message):
            // MODERN: ContentUnavailableView (iOS 17) standardizes the
            // empty-state layout that used to be a hand-rolled VStack of
            // image/title/caption in every app.
            ContentUnavailableView(
                title,
                systemImage: "tray",
                description: Text(message)
            )

        case .error(let message, let isRetryable):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                // WHY the retry button is conditional: offering "Try again"
                // on a non-retryable failure (not found, bad data) is a lie
                // that costs the user a tap to discover.
                if isRetryable, let onRetry {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.listRetryButton)
                }
            }
        }
    }
}

#Preview("Loading") {
    StateContainer(state: .loading) { Text("content") }
}

#Preview("Empty") {
    StateContainer(state: .empty(
        title: "No loans yet",
        message: "When you finance a device, it will show up here."
    )) { Text("content") }
}

#Preview("Retryable error") {
    StateContainer(
        state: .error(message: "You appear to be offline.", isRetryable: true),
        onRetry: {}
    ) { Text("content") }
}

#Preview("Non-retryable error") {
    StateContainer(
        state: .error(message: "We couldn't find that.", isRetryable: false)
    ) { Text("content") }
}
