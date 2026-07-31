import Foundation
import LoanPayDomain

/// Temporary `OutboxEnqueuing` implementation: accepts and counts requests,
/// logs the type, delivers nothing.
///
/// ARCH: features are written against the enqueue seam from day one, so
/// when the persistent outbox lands the swipe action does not change — only
/// the composition root swaps this stub out. The stub is honest about its
/// nature: it logs loudly so nobody mistakes "accepted" for "delivered".
actor LoggedOutboxStub: OutboxEnqueuing {
    private let logger: any AppLogger
    private(set) var enqueuedCount = 0

    init(logger: any AppLogger) {
        self.logger = logger
    }

    func enqueue(_ payload: OutboxPayload) async throws {
        enqueuedCount += 1
        logger.log(.warning, category: .outbox,
                   "enqueue accepted by stub (NOT persisted, NOT delivered): \(payload.typeDescription)")
    }
}

extension OutboxPayload {
    // FINTECH: the loggable shape of a payload is its TYPE, never its
    // contents — topics and loan ids stay out of logs.
    var typeDescription: String {
        switch self {
        case .supportCallback: "supportCallback"
        }
    }
}
