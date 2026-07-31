import Foundation
import Testing
import LoanPayDomain
import LoanPayFeatureKit
@testable import SupportFeature

actor EnqueueSpy: OutboxEnqueuing {
    private(set) var enqueued: [OutboxPayload] = []
    var shouldFail = false

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func enqueue(_ payload: OutboxPayload) async throws {
        if shouldFail { throw DomainError.unknown }
        enqueued.append(payload)
    }
}

@MainActor
@Suite struct SupportCallbackViewModelTests {
    @Test func requestEnqueuesTheSelectedTopicAndLoan() async {
        let outbox = EnqueueSpy()
        let viewModel = SupportCallbackViewModel(outbox: outbox, loanID: LoanID("loan-3"))
        viewModel.selectedTopicID = "payments"

        viewModel.requestCallback()
        await viewModel.enqueueTask?.value

        #expect(viewModel.state == .queued)
        await #expect(outbox.enqueued == [.supportCallback(topic: "payments", loanID: LoanID("loan-3"))])
    }

    @Test func noTopicMeansNoRequest() async {
        let outbox = EnqueueSpy()
        let viewModel = SupportCallbackViewModel(outbox: outbox)

        viewModel.requestCallback()
        await viewModel.enqueueTask?.value

        #expect(viewModel.state == .choosing)
        await #expect(outbox.enqueued.isEmpty)
    }

    @Test func validPreselectionSticksUnknownIsIgnored() {
        let known = SupportCallbackViewModel(outbox: EnqueueSpy(), preselectedTopicID: "device")
        #expect(known.selectedTopicID == "device")

        let unknown = SupportCallbackViewModel(outbox: EnqueueSpy(), preselectedTopicID: "ransomware")
        #expect(unknown.selectedTopicID == nil)
    }

    @Test func enqueueFailureSurfaces() async {
        let outbox = EnqueueSpy()
        await outbox.setShouldFail(true)
        let viewModel = SupportCallbackViewModel(outbox: outbox)
        viewModel.selectedTopicID = "other"

        viewModel.requestCallback()
        await viewModel.enqueueTask?.value

        #expect(viewModel.state == .failed)
    }
}

@Suite struct SupportDeepLinkHandlerTests {
    private let handler = SupportDeepLinkHandler()

    @Test func callbackWithTopicParses() {
        let outcome = handler.handle(pathComponents: ["callback", "payments"], isAuthenticated: true)
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.supportCallback(topic: "payments")]
        )))
    }

    @Test func bareCallbackParsesWithNoTopic() {
        let outcome = handler.handle(pathComponents: ["callback"], isAuthenticated: true)
        #expect(outcome == .handled(NavigationIntent(
            base: .loanList,
            routes: [.supportCallback(topic: nil)]
        )))
    }

    @Test func loggedOutRequiresAuth() {
        let outcome = handler.handle(pathComponents: ["callback", "device"], isAuthenticated: false)
        #expect(outcome == .requiresAuth(NavigationIntent(
            base: .loanList,
            routes: [.supportCallback(topic: "device")]
        )))
    }

    @Test(arguments: [
        ["callbacks"],
        ["callback", "bad topic!"],
        ["callback", "a", "b"],
        [String](),
    ])
    func malformedShapesAreNotRecognized(components: [String]) {
        #expect(handler.handle(pathComponents: components, isAuthenticated: true) == .notRecognized)
    }
}
