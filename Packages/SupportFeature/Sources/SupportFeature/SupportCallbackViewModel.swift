import Foundation
import Observation
import LoanPayDomain

@Observable
@MainActor
public final class SupportCallbackViewModel {
    public enum State: Equatable {
        case choosing
        /// Accepted into the queue — NOT delivered. The copy on the screen
        /// is explicit about that difference; promising "we got it" for a
        /// write still sitting on the device would be a lie the first
        /// airplane-mode user discovers.
        case queued
        case failed
    }

    public struct Topic: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let icon: String
    }

    public static let topics: [Topic] = [
        Topic(id: "payments", title: "A payment or my balance", icon: "creditcard"),
        Topic(id: "device", title: "My device", icon: "iphone"),
        Topic(id: "loan-terms", title: "My loan terms", icon: "doc.text"),
        Topic(id: "other", title: "Something else", icon: "questionmark.circle"),
    ]

    public private(set) var state: State = .choosing
    public var selectedTopicID: String?

    @ObservationIgnored private(set) var enqueueTask: Task<Void, Never>?

    private let outbox: any OutboxEnqueuing
    private let loanID: LoanID?

    public init(outbox: any OutboxEnqueuing, preselectedTopicID: String? = nil, loanID: LoanID? = nil) {
        self.outbox = outbox
        self.loanID = loanID
        // Deep links (support/callback/<topic>) preselect; unknown ids are
        // simply ignored and the user picks by hand.
        if let preselectedTopicID, Self.topics.contains(where: { $0.id == preselectedTopicID }) {
            self.selectedTopicID = preselectedTopicID
        }
    }

    public func requestCallback() {
        guard state == .choosing, let topicID = selectedTopicID else { return }
        enqueueTask = Task { [outbox, loanID] in
            do {
                try await outbox.enqueue(.supportCallback(topic: topicID, loanID: loanID))
                self.state = .queued
            } catch {
                self.state = .failed
            }
        }
    }
}
