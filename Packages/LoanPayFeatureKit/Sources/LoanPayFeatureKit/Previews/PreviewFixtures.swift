import Foundation
import LoanPayDomain

/// Canonical sample entities for previews. Deliberately small and fixed —
/// per-screen preview *scenarios* live with each feature; these are just
/// the raw materials they share.
public enum PreviewFixtures {
    public static let activeLoan = Loan(
        id: LoanID("preview-active"),
        deviceModel: "Galaxy A15",
        deviceImageURL: URL(string: "https://picsum.photos/seed/preview-active/300/300"),
        principal: usd("240.00"),
        outstandingBalance: usd("140.00"),
        monthlyInstallment: usd("20.00"),
        status: .active,
        nextInstallmentDue: date("2026-08-10T00:00:00Z")
    )

    public static let overdueLoan = Loan(
        id: LoanID("preview-overdue"),
        deviceModel: "Redmi 13C",
        deviceImageURL: nil,
        principal: usd("180.00"),
        outstandingBalance: usd("150.00"),
        monthlyInstallment: usd("15.00"),
        status: .overdue,
        nextInstallmentDue: date("2026-07-12T00:00:00Z")
    )

    public static let paidOffLoan = Loan(
        id: LoanID("preview-paid"),
        deviceModel: "Tecno Spark 20",
        deviceImageURL: URL(string: "https://picsum.photos/seed/preview-paid/300/300"),
        principal: usd("204.00"),
        outstandingBalance: usd("0.00"),
        monthlyInstallment: usd("17.00"),
        status: .paidOff,
        nextInstallmentDue: nil
    )

    public static let paymentMethods: [PaymentMethod] = [
        PaymentMethod(id: PaymentMethodID("pm-wallet"), displayName: "M-PESA Wallet", kind: .mobileWallet),
        PaymentMethod(id: PaymentMethodID("pm-card"), displayName: "Visa •••• 4242", kind: .bankCard),
        PaymentMethod(id: PaymentMethodID("pm-agent"), displayName: "Cash at Agent", kind: .cashAgent),
    ]

    private static func usd(_ value: String) -> Money {
        Money(amount: Decimal(string: value)!, currencyCode: "USD")
    }

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}
