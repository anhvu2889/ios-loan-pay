# CODEBASE_GUIDE — harvested from the code and its teaching tags

Read this with the code open. Every claim below points at a file that
proves it; the `// WHY:` `// FINTECH:` `// ARCH:` `// MODERN:` `// LANG:`
tags at those sites carry the full reasoning.

---

## Layer by layer

### LoanPayDomain — what the app IS
**Responsibility:** entities, rules, contracts. Imports Foundation only
(the commented-out `import SwiftUI` in `LoanPayDomain.swift` documents the
boundary the manifest enforces).
**Best practices, with proving files:**
- Money is Decimal-only with a throwing add — `Money.swift`
- Retry-ability decided once, on the error type — `DomainError.swift`
- Structured concurrency with a cap and stable output order —
  `LoadPortfolioSummaryUseCase.swift`
- Time as an injected seam — `Sleeper.swift`, `RetryPolicy.swift`
**Without this you'd see:** balances drifting by fractions of a cent
(Double math); every screen re-deciding what's retryable and disagreeing;
a summary that reorders per refresh.
**Key quotes:**
> "FINTECH: a summary built from per-loan quotes can be *partial* — rather
> than hiding that, the summary carries exactly which loans made it in."
> (`PortfolioSummary.swift`)
> "WHY: non-retryable DomainErrors and non-domain errors … propagate on
> the first attempt — retrying them would just repeat the same failure
> slower." (`RetryPolicy.swift`)

### LoanPayData — where truth comes from
**Responsibility:** implement Domain contracts; translate wire ↔ domain
and transport-error ↔ DomainError, exactly once.
**Best practices, with proving files:**
- Strict wire-amount grammar (Decimal(string:) is a PREFIX parser: "14o.50"
  parses as 14!) — `WireAmount.swift`
- One error translation point, cancellation never translated —
  `ErrorMapper.swift`
- Injected failures throw TRANSPORT errors so the mapper path is tested,
  not bypassed — `MockBehavior.swift`
- SWR as a decorator over ANY repository — `CachedLoanRepository.swift`
- Idempotency simulated server-side so client key-reuse means something —
  `MockPaymentRepository.swift`
- Durable queue with reclaimable inflight state — `OutboxStore.swift`,
  `OutboxDrainer.swift`
- Pins on SPKI keys, never leaf certs, with a written rotation story —
  `CertificatePinning.swift`
**Without this you'd see:** a corrupt amount silently truncated instead of
rejected; ViewModels switching on URLError; a cache that vanishes under
disk pressure (see the Application-Support WHY in `FileCacheDisk.swift`);
double support tickets per retry; a pinning outage on the next cert renewal.
**Key quotes:**
> "FINTECH: the dedupe check runs BEFORE failure injection so a replayed
> key returns the original receipt even while the endpoint is failing."
> (`MockPaymentRepository.swift`)
> "pinning without a rotation plan is a scheduled outage" — the full plan
> at `CertificatePinning.swift`.

### LoanPayFeatureKit — the shared presentation floor
**Responsibility:** typed routes, deep-link vocabulary, design system,
preview fakes. Depends only on Domain; it's what lets feature packages
never import each other.
**Best practices, with proving files:**
- ONE money-rendering path (formatted + spoken + privacySensitive) —
  `AmountText.swift`
- Status never color-only — `StatusBadge.swift`
- Style + disable fused so the safe form is the short form —
  `PrimaryButtonStyle.swift`
- Display state hoisted out of the generic (nested types specialize with
  their generic parent!) — `ContentDisplayState.swift`
- Untrusted-input validation shared, not hand-rolled per feature —
  `DeepLinkParameter.swift`
**Without this you'd see:** VoiceOver spelling balances digit-by-digit;
red/green-only status unreadable to 1-in-12 men; `StateContainer<A>.
DisplayState` vs `<B>` type errors at every call site.

### Feature packages (PaymentFeature, SupportFeature)
**Responsibility:** screens + ViewModels + flow logic behind ONE public
entry each. Domain + FeatureKit only.
**Best practices, with proving files:**
- THE state-machine exemplar: one enum, one synchronous `send`, owned
  tasks, isDismissed freeze — `PaymentViewModel.swift`
- Idempotency key lifecycle in one comment block at the top of that file
- Honest queued≠delivered copy — `SupportCallbackView.swift`
- Features parse their own deep-link remainder —
  `PaymentDeepLinkHandler.swift`, `SupportDeepLinkHandler.swift`
**Without this you'd see:** the classic double-tap double-charge (killed
by pattern matching, not button-disabling reflexes); a retry that mints a
fresh key and pays twice after a timeout that actually landed.
**Key quote:**
> "LANG: this case IS the double-tap defense … One tap, one transition,
> one submission — enforced by pattern matching, not by disabling buttons
> fast enough." (`PaymentViewModel.swift`)

### App target — composition and journeys
**Responsibility:** the only place concrete types meet (`AppDependencies`),
coordinators, auth/session, in-app features (list/detail/application),
hygiene.
**Best practices, with proving files:**
- Typed `[AppRoute]` path with a real unwind API (readable ≠ opaque
  NavigationPath) — `AppCoordinator.swift`
- Consume-once pending intent, enforced structurally —
  `AppCoordinator.swift`
- Pagination dedupe as a set-insert invariant — `LoanListViewModel.swift`
- Debounce by task replacement + explicit post-sleep checkCancellation —
  `LoanListViewModel.swift`
- Token held OUT of the store until the biometric gate passes —
  `AuthFlowCoordinator.swift`
- One logout sweep with registered wipes — `SessionStore.swift`
- Detect-and-signal, never hard-block — `JailbreakSensor.swift`
- Honest BGTaskScheduler caveats + debugger command —
  `OutboxBackgroundRefresh.swift`
**Without this you'd see:** a page loading twice per onAppear storm; a
cancelled search firing its stale query; a found phone reading balances
(possession ≠ presence); PII surviving logout.

---

## Language-decisions index (keyword → file:symbol → rule)

| Keyword | Where | The rule the site teaches |
|---|---|---|
| `private(set)` | `LoanListViewModel.state`, `AppCoordinator.path` | views read, methods mutate; every transition is greppable |
| `final class` | every ViewModel | @Observable + inheritance is a debugging trap; nothing here is designed for subclassing |
| actor | `SessionStore`, `CacheStore`, `OutboxStore`, `MockBehavior`, `MockPaymentRepository` | shared mutable state crossed by tasks → isolation by construction |
| `@unchecked Sendable` + NSLock | `RuntimeOverridableFlags`, `PinnedSessionDelegate` | when a protocol demands SYNCHRONOUS access an actor can't give; the lock discipline is documented at the site |
| `@escaping` | `LoginViewModel.onSuccess` | the hand-off outlives the call; the VM can't navigate, tests capture the value |
| non-`@escaping` | `RetryPolicy.execute(_:)` | awaited inline, never stored — the compiler proves the lifetime |
| `some` vs `any` | `SupportFeatureEntry.makeDeepLinkHandler() -> some DeepLinkHandling` vs `any LoanRepository` fields | `some`: one concrete type, statically known; `any`: heterogeneous storage/injection |
| `[weak self]` | `LoanListViewModel` owned tasks | a task that outlives its screen must not resurrect it |
| `nonisolated(unsafe)` | `StubURLProtocol.handler` (tests) | honest about global test state + the `.serialized` discipline that makes it safe |
| `@autoclosure` | `AppLogger.log` | build the message only if it will be emitted |
| `lazy`-equivalent eager decode | `BundledFeatureFlags.init` | hot-path reads must be a dictionary hit, not repeated I/O |
| phantom generic | `Identifier<Entity>` | a payment-method id where a loan id belongs is a compile error |
| `isolated (any Actor)? = #isolation` | `ErrorMapper.mapping` | isolation-polymorphic helpers stay on the caller's actor |
| `#if DEBUG` at file scope | `DebugMenuView` | the strongest "never ships" guarantee is not compiling it |

## Quick reference (concept → file → symbol)

| Concept | File | Symbol |
|---|---|---|
| State-machine exemplar | Packages/PaymentFeature/.../PaymentViewModel.swift | `send(_:)` |
| Idempotency lifecycle | same | `idempotencyKey` |
| Error translation | Packages/LoanPayData/.../ErrorMapper.swift | `mapping` |
| Capped TaskGroup | Packages/LoanPayDomain/.../LoadPortfolioSummaryUseCase.swift | `summary(for:currencyCode:)` |
| Bounded auto-retry | Packages/LoanPayDomain/.../RetryPolicy.swift | `initialListLoad` |
| SWR stream | Packages/LoanPayData/.../CachedLoanRepository.swift | `snapshotStream` |
| Two-tier cache | Packages/LoanPayData/.../CacheStore.swift | `load(_:forKey:)` |
| Outbox drain | Packages/LoanPayData/.../OutboxDrainer.swift | `drainNow` |
| Pin evaluation | Packages/LoanPayData/.../CertificatePinning.swift | `evaluate(host:spkiHashes:)` |
| Unwind API | loanpay/App/AppCoordinator.swift | `unwind(to:)`, `dismissAllAndUnwind` |
| Deep-link dispatch | loanpay/Navigation/DeepLinkDispatcher.swift | `dispatch(_:isAuthenticated:)` |
| Pending intent | loanpay/App/AppCoordinator.swift | `consumePendingIntent` |
| Logout sweep | loanpay/Auth/SessionStore.swift | `clearAll` |
| Inactivity timeout | loanpay/Auth/AuthFlowCoordinator.swift | `sceneDidBecomeActive(at:)` |
| Money rendering | Packages/LoanPayFeatureKit/.../AmountText.swift | `AmountText` |
| Debounce | loanpay/Features/LoanList/LoanListViewModel.swift | `searchTextChanged` |
| Pagination dedupe | same | `startLoadingPage` |
| Continuation gating (tests) | loanpayTests/AppTestSupport.swift | `Gate` |
