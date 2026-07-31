# LoanPay — Final Report (STACKED run, 2026-07-30 → 07-31)

## What was built

Fourteen feature clusters, delivered as PRs #2–#15 (plus recovery roll-up
#6), covering every feature in the brief: loan list (pagination, search,
sections, portfolio TaskGroup summary), detail + Swift Charts, the payment
state machine with the full idempotency-key lifecycle, the application
form, auth/session/biometrics, typed navigation + hierarchical deep links,
offline read (two-tier cache + SWR) and write (persistent outbox + drainer
+ BG refresh), the reference URLSession path with a local mock server,
the fintech security layer, and hygiene/release engineering/docs.

## Test counts (all green)

| Suite | Framework | Tests |
|---|---|---|
| LoanPayDomain | Swift Testing | 22 |
| LoanPayData | Swift Testing | 71 |
| PaymentFeature | Swift Testing | 12 |
| SupportFeature | Swift Testing | 8 |
| loanpayTests (app) | Swift Testing | 69 |
| LoanPayXCTestRosetta | XCTest | 13 |
| **Total** | | **195** |

Zero real sleeps anywhere: continuation gates (`Gate`, `KeyedGate`) +
injected `Sleeper`s/clocks only. The release audit
(`Scripts/release-audit.sh`) verifies the Release binary contains no
`StubURLProtocol` symbol and the Release Info.plist has no ATS exceptions
— both pass.

## Package graph

```
                 ┌────────────────────┐
                 │   loanpay (app)    │  composition root · coordinators
                 └┬────┬────┬────┬───┘   auth · LoanList/Detail/Application
                  │    │    │    │
       ┌──────────┘    │    │    └───────────┐
       ▼               ▼    ▼                ▼
 PaymentFeature  SupportFeature  LoanPayData │
       │               │             │       │
       └───────┬───────┘             │       │
               ▼                     │       ▼
       LoanPayFeatureKit             │  LoanPayFeatureKit
               │                     │       │
               └──────────┬──────────┴───────┘
                          ▼
                    LoanPayDomain  (Foundation only)

 LoanPayRosetta (test-only) ──▶ Domain + Data
```

## Add FeatureX in 5 steps, touching only its package (+1 registration line)

1. `Packages/FeatureX/Package.swift` — depend on LoanPayDomain +
   LoanPayFeatureKit (never Data, never a sibling).
2. Write `FeatureXViewModel` (@Observable @MainActor final, private(set)
   state enum; a synchronous `send(_:)` if the flow is complex) against
   Domain contracts.
3. Write views taking values + closures; add per-state #Previews using
   FeatureKit's preview fakes.
4. Expose ONE public `FeatureXEntry: FeatureEntry` (featureID, view
   factory, `makeDeepLinkHandler()` for `loanpay://featurex/...`).
5. Add a route case to `AppRoute` if it pushes, then register in
   `FeatureRegistration.registerAll` — the single app-side line — and hand
   it dependencies from `AppDependencies`.

## Flags inventory (`loanpay/Resources/flags.json`)

| Flag | State | Owner | Purpose / removal |
|---|---|---|---|
| `search_enabled` | on | growth | Gates list search during ranking validation. Remove after 100% + one train. |
| `payments_enabled` | on | payments | Kill switch → maintenance state, `.pay` no-op. **Permanent.** |

## Release manifest (demo train `v1.0.0-demo`)

`Releases/1.0.0-demo-manifest.json`: version, cut SHA
(`121e5bc…`), cut timestamp, and the full flag state above — "what
exactly shipped" as a committed file. Tag `v1.0.0-demo` points at the cut.

## Suggested reading order

1. `ARCHITECTURE.md` (1 minute) then `Packages/LoanPayDomain/Sources/…/
   Money.swift` + `DomainError.swift` — the two value systems everything
   rides on.
2. `MockBehavior.swift` → `ErrorMapper.swift` — how failures are made and
   translated.
3. `PaymentViewModel.swift` top to bottom — the exemplar; every pattern in
   the codebase appears here in its strictest form.
4. `LoanListViewModel.swift` — the same ideas, relaxed to fit a simpler
   screen (methods instead of send; note what was NOT carried over and
   why).
5. `CachedLoanRepository.swift` + `OutboxStore.swift`/`OutboxDrainer.swift`
   — offline read and write.
6. `AppCoordinator.swift` + `DeepLinkDispatcher.swift` + the feature
   deep-link handlers — navigation as data.
7. `CertificatePinning.swift` + `SECURITY.md` — the security layer.
8. `loanpayTests/AppTestSupport.swift` (`Gate`) — how the whole suite runs
   with zero sleeps. Then `LoanPayRosetta` with `XCTestPrimer.swift`.
9. `CODEBASE_GUIDE.md` for the full index.

## Deviations & incidents (honest ledger)

- **PR base change mid-run** (user request): all PRs now target `main`.
  PRs #3–#5 had already merged into their stack parents — recovered with
  roll-up PR #6 (tree-identical, verified).
- Debug menu is app-owned; per-feature contribution interfaces exist as a
  seam (`FeatureEntry`) but no feature contributes a section yet.
- Environment switch applies at next launch (honest object-graph reality).
- Project/scheme name is lowercase `loanpay` (pre-existing); kept to avoid
  churn.

## MERGE RUNBOOK

All open PRs (#6–#15… plus this cluster's PR) target `main`, but the
BRANCHES still build on one another — each contains its ancestors'
commits. Merge strictly bottom-up and each PR's effective diff collapses
to its own cluster.

1. Merge ONE PR at a time, in number order: **#6 (roll-up) → #7 → #8 → #9
   → #10 → #11 → #12 → #13 → #14 → #15 → #16**, with **regular merge
   commits — never squash** (squash rewrites history and breaks every
   branch stacked above).
2. After each merge, refresh the next PR and confirm its base still reads
   `main` and its diff shows only its own cluster before merging. Verify
   from the CLI with:
   `gh pr view <n> --json baseRefName`
3. Safer one-liner per PR (pins the exact head commit you reviewed):
   ```sh
   gh pr merge <n> --merge --match-head-commit $(gh pr view <n> --json headRefOid -q .headRefOid)
   ```
   and ALWAYS confirm the base first:
   ```sh
   test "$(gh pr view <n> --json baseRefName -q .baseRefName)" = "main" || echo "STOP: base not main"
   ```
4. After the last merge, sanity-check before deleting branches:
   ```sh
   git fetch && git log origin/main --oneline | head -40
   ```
   should show every cluster's commits; then delete the `feature/*`
   branches. Also push the demo tag if wanted: `git push origin v1.0.0-demo`.

**Recovery note:** if a merge ever lands in a feature branch by mistake
(the stack-cascade — it happened once in this run), the fix is a single
roll-up PR from the stack's tip → `main` with a regular merge commit,
after verifying the tip's tree is identical to the intended final state
(`git diff <tip> <expected>` empty). PR #6 is the worked example.
