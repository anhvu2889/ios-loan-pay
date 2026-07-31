# IMPLEMENTATION_PLAN — as built

## Blueprint

Five local SPM packages under one app target (see ARCHITECTURE.md for the
graph). The build order was dependency order: Domain → Data → FeatureKit →
features (list/detail in-app, Payment/Support as packages) → cross-cutting
capability layers (auth, navigation, offline read/write, remote path,
security) → hygiene/release/docs. Every slice landed as a PR with its
tests; `main` was releasable after every merge.

## File breakdown (what lives where)

| Area | Files (primary) |
|---|---|
| **LoanPayDomain** | Entities (`Money`, `Loan`, `LoanDetail`, `Installment`, `LoanPage`, `PayoffQuote`, `PaymentMethod/Request/Receipt`, `IdempotencyKey`, `PortfolioSummary`, `Snapshot`, outbox types, `LoanApplication`) · `DomainError` · contracts (`LoanRepository`, `PaymentRepository`, `SnapshotLoanReading`, `OutboxEnqueuing/Delivering`, `TokenStorage`, `FeatureFlags`, `AppLogger`, `AnalyticsClient`, `ConnectivityMonitoring`, `Sleeper`) · use cases (`LoadLoansUseCase`, `LoadPortfolioSummaryUseCase`) · `RetryPolicy` |
| **LoanPayData** | DTOs + `WireAmount` · `ErrorMapper` · mock backend (`MockBehavior`, `MockLoanRepository`, `MockPaymentRepository`, `MockLoanApplicationRepository`, `MockOutboxDelivery`, fixtures) · offline (`CacheStore` two-tier, `CacheDisk`, `CachedLoanRepository`, `OutboxStore`, `OutboxDrainer`, `ConnectivityMonitor`) · remote (`URLSessionAPIClient`, `RemoteLoanRepository`, `RemotePaymentRepository`, `CertificatePinning`, `PinnedSessionDelegate`) |
| **LoanPayFeatureKit** | `AppRoute`, `FeatureEntry`, deep-link vocabulary (`NavigationIntent`, `DeepLinkOutcome`, `DeepLinkHandling`, `DeepLinkParameter`) · design system (`AmountText`, `PrimaryButtonStyle`, `StatusBadge`, `CardContainer`, `StateContainer`, `ContentDisplayState`, `SyncBadge`, `FreshnessLabel`, `AccessibilityID`) · preview fakes |
| **PaymentFeature** | `PaymentState/Action/Context`, `PaymentViewModel` (the exemplar), flow views, `PaymentDeepLinkHandler`, `PaymentFeatureEntry` |
| **SupportFeature** | callback VM + view, `SupportDeepLinkHandler`, `SupportFeatureEntry` |
| **app target** | `AppDependencies`, `AppCoordinator` (typed path + unwind API + pending intent), `RootView`, `FeatureRegistration`, `DeepLinkDispatcher`, auth (`SessionStore`, `KeychainWrapper`, `AuthFlowCoordinator`, biometrics, login/gate screens), LoanList + LoanDetail + LoanApplication features, hygiene (`OSAppLogger`, `ConsoleAnalytics`, flags, `AppEnvironment`), `JailbreakSensor`, `OutboxBackgroundRefresh`, debug menu |
| **LoanPayRosetta** | XCTest translations + primer (test-only) |

## Decision log — "at what scale this earns its cost; below it I'd cut"

| Decision | Earns its cost when… | Below that scale I'd cut to… |
|---|---|---|
| Local SPM packages per layer/feature | ≥2 teams or ≥2 features evolving in parallel; boundary violations start appearing in review | folders + discipline in one target |
| Phantom-typed `Identifier<Entity>` | more than two id types circulate (loan/method/payment) | bare `String` ids |
| Synchronous `send(_:)` state machine | any flow where a double-fire moves money or duplicates writes | plain async methods (the loan list does exactly this) |
| SWR snapshot streams | users on flaky networks open the app daily; blank screens cost trust | plain fetch + spinner |
| Persistent outbox + drainer + BG task | writes must survive process death and offline days | fire-and-forget with a retry toast |
| SPKI pinning + backup pin | real money + hostile networks; you control the server keys | system TLS only |
| Two-tier cache | list/detail re-render often enough that disk+decode shows in profiles | file-only cache |
| Per-feature deep-link handlers + prefix table | ≥3 features own links; one URL parser becomes a merge magnet | one switch in the app |
| `Sleeper`/clock injection everywhere | any CI where a flaky sleep costs a re-run (i.e., always, honestly) | — (this one I would not cut) |
| Debug menu + failure injection | more than one person tests error states | a hardcoded `#if DEBUG` toggle |
| Rosetta XCTest target | team migrating between test frameworks | delete after migration completes |
| Feature packages (Payment/Support) vs in-app (LoanList/Auth) | extraction recorded as deliberate: extract when a second team or app needs them | keep in-app (as LoanList/Auth are) |

## Deviations from the original brief (all deliberate, all recorded)

- PR bases: switched mid-run to "every PR targets main" at the user's
  request; PRs #3–#5 had merged into stack parents first, recovered by
  roll-up PR #6.
- Debug menu is app-owned rather than assembled from per-feature
  contribution interfaces — the seam (`FeatureEntry`) exists; contributions
  can migrate onto it when a feature actually needs to add a section.
- Environment switching takes effect on next launch (honest, vs re-wiring
  a live object graph).
