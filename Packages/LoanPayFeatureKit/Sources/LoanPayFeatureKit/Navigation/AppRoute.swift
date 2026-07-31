import Foundation
import LoanPayDomain

// ARCH: the one route vocabulary the whole app pushes onto its
// NavigationStack. A TYPED array of these — not an opaque NavigationPath —
// is what makes unwind(to:), deep-link resume and "is the confirmation
// still reachable?" answerable questions: you can only reason about a path
// you can read.
//
// WHY payment is absent: the payment flow is presented as a sheet (its own
// coordinator owns an internal state machine), not pushed. Routes here are
// push destinations only; modality is a different axis and mixing the two
// in one enum breeds "pop the sheet" bugs.
public enum AppRoute: Hashable, Sendable {
    case loanDetail(LoanID)
    case applyForLoan
    case supportCallback(topic: String?)
}
