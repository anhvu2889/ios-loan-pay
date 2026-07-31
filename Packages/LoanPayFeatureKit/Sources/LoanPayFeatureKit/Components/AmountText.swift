import SwiftUI
import LoanPayDomain

/// THE way money reaches a screen. Every visible amount in the app renders
/// through this view — formatted for the eye, spoken in words for
/// VoiceOver, and hidden in the app switcher.
///
/// FINTECH: centralizing the rendering path is what makes the three rules
/// (single format, spoken-not-spelled, privacy redaction) enforceable —
/// a raw `Text(money.formatted())` at a call site silently drops two of
/// them, which is why SwiftLint flags Text+formatted pairings outside this
/// file.
public struct AmountText: View {
    private let money: Money

    public init(_ money: Money) {
        self.money = money
    }

    public var body: some View {
        Text(money.formatted())
            // WHY: tabular digits keep amount columns from shimmering as
            // values change width during refreshes.
            .monospacedDigit()
            .accessibilityLabel(money.spokenDescription())
            // FINTECH: balances must never appear in the app switcher
            // snapshot. This marks the view; the scene-level
            // `.redacted(reason: .privacy)` applied when the app resigns
            // active is what actually blanks it.
            .privacySensitive()
    }
}

#Preview("Amounts") {
    VStack(alignment: .trailing, spacing: 12) {
        AmountText(Money(amount: 1250.50, currencyCode: "USD"))
        AmountText(Money(amount: 0, currencyCode: "USD"))
            .font(.title.bold())
        AmountText(Money(amount: 88, currencyCode: "USD"))
            .foregroundStyle(.red)
    }
    .padding()
}

#Preview("Redacted (app switcher)") {
    AmountText(Money(amount: 1250.50, currencyCode: "USD"))
        .redacted(reason: .privacy)
        .padding()
}
