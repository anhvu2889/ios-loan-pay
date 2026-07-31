# PARITY.md — construct-by-construct map between the twins

The core deliverable for an iOS engineer reading this repo. Every row names
the construct, both implementations, and whether the twins are the SAME idea
in two syntaxes or genuinely DIVERGENT — with the one-line reason when they
are.

Legend: **SAME** = same concept, idiomatic spelling differs.
**DIVERGENT** = the platforms pushed the designs apart; reason given.

## State & UI

| Construct | iOS | Android | Verdict |
|---|---|---|---|
| Screen state exposure | `@Observable` model, properties observed implicitly by `body` | `StateFlow<UiState>` collected explicitly (`LoanListViewModel`) | DIVERGENT — Compose makes the subscription an explicit, lifecycle-aware call; SwiftUI hides it in body tracking |
| Observation in UI | body re-evaluates on change | `collectAsStateWithLifecycle` (`LoansFeatureEntry`) | DIVERGENT — Android must SAY it stops observing off-screen; iOS gets it because body simply doesn't run |
| Async work ownership | owned task handles, cancelled on dismiss/disappear (`cancelOngoingWork()`, `send(.dismiss)`) | `viewModelScope` Jobs (`PaymentViewModel`) | SAME — but Android's cancellation is framework-wired, iOS's is hand-written |
| Effect on enter/param change | `.task` + `.onChange(of:)` | `LaunchedEffect(key)` (`PaymentTrigger`, success haptics) | SAME |
| UI-local state | `@State` | `remember` / `rememberSaveable` (`LoanRow` menu) | SAME |
| Value-carrying closed types | enum with associated values (`PaymentState`) | sealed interface with data classes (`PaymentState.kt`) | SAME — Kotlin spells "associated value" as a constructor property; exhaustive `when` = exhaustive `switch` |
| Component inputs | values + closures | values + lambdas, never ViewModels (`LoanRow`) | SAME |

## Concurrency & flows

| Construct | iOS | Android | Verdict |
|---|---|---|---|
| Search debounce | hand-rolled: task replacement + injected sleeper (`LoanListViewModel`) | `debounce(300)` flow operator (`LoanListViewModel.observeQuery`) | DIVERGENT — Kotlin ships the pattern as a named, virtual-time-testable operator; Swift builds it from primitives |
| Capped parallel fan-out | `TaskGroup`, seed-N-then-refill window (`LoadPortfolioSummaryUseCase`) | `coroutineScope` + `async`/`awaitAll` + `Semaphore(4)` (`loadSummary`) | DIVERGENT — the Semaphore caps concurrency declaratively; TaskGroup meters manually |
| Parallel fail-together load | `async let` + `try await` | `coroutineScope` + `async`/`awaitAll` (`PaymentViewModel.loadContext`) | SAME — both cancel siblings on first failure |
| Listener → stream bridge | `AsyncStream` over NWPathMonitor | `callbackFlow` over NetworkCallback (`AndroidConnectivityMonitor`) | SAME |
| Cold→hot bridging | `@Observable` is hot by default | `stateIn(WhileSubscribed)` (`AppSessionViewModel`) | DIVERGENT — Kotlin makes the sharing policy an explicit, tunable argument |
| Cancellation etiquette | don't catch `CancellationError` broadly (`ErrorMapper` rethrows it unmapped) | rethrow `CancellationException` unmapped (`MappingCall.kt`) | SAME — both punish the same mistake with zombie work |

## Background & persistence

| Construct | iOS | Android | Verdict |
|---|---|---|---|
| Background sync | `BGTaskScheduler` — the app REQUESTS, the OS grants opportunistically (`OutboxBackgroundRefresh`) | `WorkManager` — constraints + GUARANTEED execution (`OutboxWorker`) | **DIVERGENT — the flagship.** Guarantee vs opportunity reshapes the design: Android's scheduled drain is the primary path; iOS must treat foreground drains as primary |
| Secret storage | Keychain (`ThisDeviceOnly`) | Keystore key + own ciphertext file (`KeystoreCipher`, `KeystoreSessionStore`) | DIVERGENT — Keychain is storage+crypto in one API; Android splits keys (Keystore) from storage (yours) |
| Auth-bound keys | Keychain access control (`biometryCurrentSet`) deliberately NOT used — session-level `LAContext` gate instead (see SECURITY.md) | `setUserAuthenticationRequired` (deliberately NOT set — session-level gate instead, see SECURITY.md) | SAME concept — both twins chose the session-level gate |
| File-at-rest protection | FileProtection classes (OS encrypts by lock state) | app-managed AES/GCM via Keystore (`FileLoanCache`) | DIVERGENT — iOS ties file crypto to device lock automatically; Android hands you a key and a decision |
| App-switcher privacy | `scenePhase` + `privacySensitive` redaction | `FLAG_SECURE` on pause (`MainActivity`) | DIVERGENT — iOS REDACTS content (per-view opt-in, keeps context); Android BLANKS the window (coarse, cannot miss a view) |

## Navigation

| Construct | iOS | Android | Verdict |
|---|---|---|---|
| Typed routes | `Hashable` route enum in `NavigationStack` path | `@Serializable` route classes (`LoansRoutes.kt`, `AppRoutes.kt`) | SAME |
| Unwind after payment | truncate the typed path array | `popBackStack<HomeRoute>(inclusive=false)` (`PaymentFeatureEntry`) | SAME — array surgery vs named operation, identical guarantee: the consumed confirmation is not back-reachable |
| Deep-link dispatch | prefix table on the URL's feature prefix (`DeepLinkDispatcher`) | `DeepLinkDispatcher` prefix table via `FeatureEntry` | SAME |
| Route decoding | typed path element | `SavedStateHandle.toRoute()` (`LoanDetailViewModel`) | SAME (payment VM reads the raw key — documented JVM-testability trade) |

## Architecture & tooling

| Construct | iOS | Android | Verdict |
|---|---|---|---|
| Modules | SPM packages | Gradle modules with `api`/`implementation` (`settings.gradle.kts`) | DIVERGENT — Gradle's api/implementation split makes transitive visibility a per-dependency decision; SPM exposes products wholesale |
| Composition root | hand-built `AppDependencies` | Hilt modules + multibinding (`LoanPayApp`, `DataModule`) | DIVERGENT — codegen'd, compile-checked graph vs explicit hand wiring; the FeatureEntry SET is the visible seam in both |
| Swipe row action | `.swipeActions` (non-destructive built in) | `SwipeToDismissBox` + `confirmValueChange=false` (`LoanRow`) | DIVERGENT — Android's dismiss component must be taught not to dismiss |
| Search UI | `.searchable` modifier (owns presentation) | M3 `SearchBar` (caller owns expansion state) (`LoanSearchBar`) | DIVERGENT — M3 hands state up; .searchable keeps it |
| Lint | SwiftLint | detekt + ktlint (`config/detekt/detekt.yml`) | SAME — detekt guards design (LargeClass/LongMethod), ktlint guards formatting |
| HTTP test double | `StubURLProtocol` inside URLSession | `MockWebServer` — a REAL socket (`RetrofitApiIntegrationTest`) | DIVERGENT — MockWebServer exercises actual connection code; URLProtocol swaps the transport out beneath the API |
| Async test determinism | gated continuations (hand-built `Gate`) | `runTest` virtual time (every VM test) | DIVERGENT — hand-built gates vs framework virtual time; see the Android twin's TESTING.md for the two philosophies |
| Cert pinning | URLSession delegate challenge handler (manual SPKI compare) | `CertificatePinner` (declarative) (`RemoteModule`) | DIVERGENT — same pins, one platform ships the machinery |
| Integrity check | jailbreak detection (Cydia paths, sandbox probes) | root detection (su paths, test-keys, writable dirs) (`RootDetector`) | SAME — different artifacts, identical detect-and-signal philosophy |
| Money type | struct over `Decimal` | data class over `BigDecimal` (`Money.kt`) | SAME — and both twins ban the platform float |
| Manual pagination | hand-rolled (no platform lib chosen) | hand-rolled, `// VS-IOS:` notes Paging3 as the platform library (`Page.kt`) | SAME by choice — Android deliberately skips Paging3 so the mechanism stays visible |
| Value-type ids | one-field phantom-generic struct (`Identifier<Entity>`) | `@JvmInline value class` (`LoanId`) | SAME — both erase at runtime |
| Reduced motion | `accessibilityReduceMotion` environment value | animator duration scale (`rememberReducedMotion`) | SAME concept, different system signal |
