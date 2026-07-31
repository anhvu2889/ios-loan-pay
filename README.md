# LoanPay

A self-practice, portfolio iOS application built with the latest iOS
technologies: a loan-management app where users track devices bought on
installment, watch repayment progress, make payments, apply for new loans,
and request support callbacks — online or offline.

Built with **zero third-party dependencies**: Foundation, SwiftUI, and
Swift Testing/XCTest only.

## Tech highlights

- **Swift 6 concurrency throughout** — async/await, actors, `async let`,
  `withThrowingTaskGroup` with capped parallelism, structured cancellation,
  owned task handles. No GCD, no Combine.
- **SwiftUI + Observation** — `@Observable` ViewModels, `NavigationStack`
  over a typed route array with a real unwind API, `.searchable` with
  suggestions and debounce, `ContentUnavailableView`, `.sensoryFeedback`,
  `.privacySensitive` scene redaction.
- **Swift Charts** — repayment progress (`BarMark` + `RuleMark`) and
  balance-over-time (`LineMark` + `AreaMark`) with composed accessibility
  summaries.
- **State-machine payment flow** — one state enum, one synchronous
  `send(_:)`, full idempotency-key lifecycle (double-tap-proof, safe
  retry-after-timeout, session-expiry recovery), remote kill switch.
- **Offline-first** — stale-while-revalidate cache (two-tier: memory over
  protected files) via `AsyncThrowingStream`, persistent outbox with a
  backoff drainer triggered by connectivity regain (`NWPathMonitor` →
  `AsyncStream`), foregrounding, and `BGAppRefreshTask`.
- **Security layer** — SPKI certificate pinning with backup-pin rotation,
  Keychain-backed session, biometric gate (`LocalAuthentication`),
  inactivity timeout, hardened deep-link parsing (fuzz-tested), one
  logout sweep for all PII stores.
- **Modular by SPM** — five local packages enforce the dependency graph;
  feature packages expose a single entry each and never import siblings.
- **195 tests, zero real sleeps** — Swift Testing first (parameterized
  suites, `#expect`/`#require`), determinism via injected clocks and
  continuation gating, plus an XCTest "Rosetta" target translating 13
  representative tests between the two frameworks.
- **Engineering hygiene** — GitHub Actions CI (build, all suites, SwiftLint
  `--strict`, secret scan, release audit), trunk-based releases with
  feature flags and snapshot manifests.

Non-obvious decisions are documented in-line where they're made, tagged
`// WHY:` (concurrency), `// FINTECH:` (money/PII/idempotency),
`// ARCH:` (boundaries), `// MODERN:` (new API vs the old way), and
`// LANG:` (language-level choices).

## Requirements

- Xcode 26+, Swift 6 toolchain
- iOS 17.0 deployment target (any iOS 17/18 simulator runs it)

## Run it

Open `loanpay.xcodeproj`, select the `loanpay` scheme, run. The app boots
against an **in-process mock backend** (JSON-fixture-backed, with simulated
latency) — no server needed. Sign in with any non-empty credentials; the
biometric gate follows.

**Debug menu:** triple-tap the "My Loans" title. From there you can inject
per-endpoint failures (offline / HTTP status / malformed JSON / flaky /
slow), flip feature flags (including the payments kill switch), and switch
backends. Compiled out of Release entirely.

**Real networking (optional):**

```sh
cd Scripts/mock-server && npx json-server db.json --port 3000
```

then pick "Localhost server" in the debug menu (or launch with
`-loanpay-environment remoteLocalhost`) and relaunch. See the
[mock server README](Scripts/mock-server/README.md).

**Deep links** (Simulator: `xcrun simctl openurl booted <url>`):
`loanpay://loans/loan-001` · `loanpay://payment/loan-001/methods` ·
`loanpay://support/callback/payments`

## Test it

195 tests across six suites, **zero real sleeps** (injected clocks +
continuation gating throughout):

```sh
swift test --package-path Packages/LoanPayDomain     # 22 — entities, use cases
swift test --package-path Packages/LoanPayData       # 71 — mappers, mocks, cache, outbox, client
swift test --package-path Packages/LoanPayRosetta    # 13 — XCTest translations
xcodebuild test -project loanpay.xcodeproj -scheme loanpay \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:loanpayTests                          # 69 — ViewModels, coordinators, security
# PaymentFeature (12) and SupportFeature (8): xcodebuild test from each package dir
```

CI ([ci.yml](.github/workflows/ci.yml)) runs all of it plus the secret
scan, SwiftLint `--strict`, and a release audit (no `StubURLProtocol`
symbol, no ATS exceptions in the Release product).

## Layout

```
loanpay/                  app target: composition root, coordinators, auth,
                          LoanList / LoanDetail / LoanApplication, debug menu
Packages/
  LoanPayDomain/          entities, rules, contracts — Foundation only
  LoanPayData/            DTOs, mappers, mock + URLSession repos, cache, outbox
  LoanPayFeatureKit/      routes, deep-link vocabulary, design system
  PaymentFeature/         the payment state machine (the exemplar)
  SupportFeature/         offline-tolerant callback requests
  LoanPayRosetta/         Swift Testing ⇄ XCTest rosetta (test-only)
Scripts/                  mock server, secret scan, release snapshot/audit
```

## Documentation

| Document | What's inside |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | The map, in under a minute |
| [CODEBASE_GUIDE.md](CODEBASE_GUIDE.md) | Layer-by-layer guide: practices with proving files, a language-decisions index, adding a feature in 5 steps |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | As-built decisions, each with the scale at which it earns its cost |
| [SECURITY.md](SECURITY.md) | Threat model, mitigations per threat, accepted risks, release checklist |
| [RELEASING.md](RELEASING.md) | Trunk-based releases with flags and short-lived release branches |
| [Scripts/mock-server/README.md](Scripts/mock-server/README.md) | Running the local json-server backend |
