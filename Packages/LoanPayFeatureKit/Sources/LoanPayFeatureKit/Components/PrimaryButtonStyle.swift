import SwiftUI

/// The app's one call-to-action button dress: full-width, prominent, with a
/// built-in in-flight state.
public struct PrimaryButtonStyle: ButtonStyle {
    private let isLoading: Bool

    public init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
            configuration.label
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor)
                .opacity(configuration.isPressed ? 0.75 : 1)
        )
        .foregroundStyle(.white)
        .opacity(isLoading ? 0.85 : 1)
    }
}

extension View {
    /// Applies the primary style AND disables the button while loading.
    ///
    /// LANG: a ButtonStyle cannot disable its own button — enablement lives
    /// on the Button, style lives beside it, and forgetting the `.disabled`
    /// half is exactly the double-tap bug this app cannot afford on "Pay".
    /// This modifier fuses the two so the safe form is the short one.
    public func primaryButton(isLoading: Bool = false) -> some View {
        buttonStyle(PrimaryButtonStyle(isLoading: isLoading))
            .disabled(isLoading)
    }
}

#Preview("States") {
    VStack(spacing: 16) {
        Button("Pay $20.00") {}
            .primaryButton()
        Button("Paying…") {}
            .primaryButton(isLoading: true)
        Button("Disabled") {}
            .primaryButton()
            .disabled(true)
    }
    .padding()
}

#Preview("Dark") {
    Button("Pay $20.00") {}
        .primaryButton()
        .padding()
        .preferredColorScheme(.dark)
}
