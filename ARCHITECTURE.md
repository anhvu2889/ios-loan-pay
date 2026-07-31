# Architecture

Clean Architecture + MVVM + unidirectional data flow, enforced by local SPM packages — the compiler polices the layer boundaries, not code review.

```
loanpay (app) ──▶ PaymentFeature ─┐
  composition     SupportFeature ─┼─▶ LoanPayFeatureKit ─▶ LoanPayDomain ◀── LoanPayData
  root, auth,     (one FeatureEntry┘   (routes, design        (entities,        (DTOs, mappers,
  coordinators,    each; no sibling     system, deep-link      use cases,        ErrorMapper, mock +
  LoanList         imports)             vocabulary)            contracts;        URLSession repos,
  in-app)                                                      Foundation only)  cache, outbox)
```

Rules: dependencies point inward; Domain imports Foundation only; Data and features never see each other; the app target is the only place concrete types meet (`AppDependencies`).
Per screen: one `@Observable @MainActor final` ViewModel, one `private(set)` state enum; complex flows route every action through one synchronous `send(_:)` (see `PaymentViewModel`, the exemplar); async work lives in owned, cancellable task handles; components receive values and closures, never ViewModels.
Money is `Decimal` end to end (strings on the wire); errors cross the data boundary exactly once through `ErrorMapper` into `DomainError`.
