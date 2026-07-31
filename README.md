# LoanPay

A teaching-grade, production-shaped iOS app for an emerging-markets fintech:
phones bought on installment, with the phone itself as collateral. Borrowers
see their loans, watch repayment progress, make installment payments, apply
for new device loans, and request support callbacks — online or offline.

**The code is the curriculum.** Every non-obvious decision is explained at
the site where it's made, with five comment tags:

| Tag | Carries |
|---|---|
| `// WHY:` | concurrency, cancellation, and actor decisions |
| `// FINTECH:` | money, PII, and idempotency rules |
| `// ARCH:` | layer boundaries and seams |
| `// MODERN:` | new-API idioms, with the pre-2021 equivalent named |
| `// LANG:` | language-level choices (`private(set)`, `final`, `some` vs `any`, …) |

Zero third-party dependencies: Foundation, SwiftUI, Swift Testing/XCTest only.

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
`-loanpay-environment remoteLocalhost`) and relaunch. See
`Scripts/mock-server/README.md`.

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

CI (`.github/workflows/ci.yml`) runs all of it plus the secret scan,
SwiftLint `--strict`, and a release audit (no `StubURLProtocol` symbol, no
ATS exceptions in the Release product).

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

## Read next

- `ARCHITECTURE.md` — the map, in under a minute
- `CODEBASE_GUIDE.md` — layer-by-layer guide harvested from the teaching tags
- `IMPLEMENTATION_PLAN.md` — as-built decisions, each with the scale at which it earns its cost
- `SECURITY.md` — threat model, mitigations, accepted risks
- `RELEASING.md` — trunk-based releases with flags and short-lived release branches
- `FINAL_REPORT.md` — test tally, package graph, how to add a feature in 5 steps
