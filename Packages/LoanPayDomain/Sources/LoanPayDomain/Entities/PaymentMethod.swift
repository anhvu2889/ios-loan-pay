import Foundation

public typealias PaymentMethodID = Identifier<PaymentMethod>

public struct PaymentMethod: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case bankCard
        case mobileWallet
        /// Cash handed to a partner agent — common where card penetration is
        /// low; the agent network is the payment rail in many of our markets.
        case cashAgent
    }

    public let id: PaymentMethodID
    public let displayName: String
    public let kind: Kind

    public init(id: PaymentMethodID, displayName: String, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
    }
}
