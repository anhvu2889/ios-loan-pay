# LoanPay — Security Overview (threat-model-lite)

## Assets

| Asset | Why it matters |
|---|---|
| Session token | Full account takeover if stolen |
| Loan PII (balances, schedules, device collateral, applicant data) | Borrower privacy; regulatory exposure |
| Payment integrity (amounts, idempotency, receipts) | Money moves exactly once, to the right place |

## Trust boundary

```
┌─────────────── device ───────────────┐        ┌──── network ────┐       ┌── server ──┐
│ UI (redacted when inactive)          │        │                 │       │            │
│ Keychain: session token              │  TLS   │ hostile Wi-Fi,  │       │ auth, risk │
│ Cache/Outbox files (FileProtection)  │═══════▶│ proxies, MITM   │──────▶│ engine,    │
│ Deep-link input (untrusted!)         │ pinned │                 │       │ ledger     │
│ Jailbreak sensors (signal only)      │        │                 │       │            │
└──────────────────────────────────────┘        └─────────────────┘       └────────────┘
```

Everything left of TLS is attacker-accessible given a stolen/modified
device; everything right of it is where enforcement actually lives. The
client's job is to make theft unprofitable and mistakes visible — the
server's job is to be the wall.

## Mitigations per threat

| Threat | Mitigation | Where |
|---|---|---|
| Network interception (MITM) | SPKI public-key pinning + backup pin, distinct `pinningViolation` error, no ATS exceptions in Release | `CertificatePinning`, `PinnedSessionDelegate` |
| Token theft from device | Keychain `WhenUnlockedThisDeviceOnly`, never UserDefaults, never synchronized | `KeychainWrapper` |
| PII read from stolen locked device | `completeFileProtection` on cache and outbox files | `FileCacheDisk`, `OutboxStore` |
| PII left after account switch | One sweep: `SessionStore.clearAll()` wipes token + cache + outbox on logout AND expiry | `SessionStore`, `AppDependencies.registerSessionWipes` |
| Shoulder-surfing / app-switcher leaks | `.privacySensitive` amounts + scene-phase redaction curtain | `AmountText`, `RootView` |
| Unattended unlocked phone | 5-minute backgrounded inactivity timeout → full session clear → login + biometric | `AuthFlowCoordinator` |
| Hostile deep links (injection, traversal, oversized) | Allow-listed identifier grammar + length cap inside every feature handler; unknown links logged (shape only) and dropped | `DeepLinkParameter`, `DeepLinkDispatcher` |
| Double charge on retry/timeout | Idempotency keys minted per intent, reused byte-identically on retry, never auto-retried | `PaymentViewModel`, `URLSessionAPIClient` |
| Modified device (jailbreak) | Detect-and-signal: risk event (type only) + dismissible soft warning; never hard-block — the sensors are bypassable, the server's risk engine is not | `JailbreakSensor` |
| Payload-poisoned logs / analytics | No amounts, names, tokens or payload values in logs; error types only in analytics | `AppLogger` contract, `AnalyticsEvent` |
| Committed credentials | `Scripts/secret-scan.sh` tripwire in CI | Scripts, CI |

## Accepted risks (deliberate)

- **Jailbreak detection is bypassable.** Accepted: it is a signal for
  server-side risk scoring, not a wall. Hard-blocking would hurt honest
  users of modified devices more than attackers.
- **Devices without any passcode pass the biometric gate** (with a logged
  signal). Accepted: `.deviceOwnerAuthentication` cannot raise a bar the
  OS doesn't have; the server still authenticates every request.
- **Stub login accepts any credentials.** Accepted: development-only stub
  behind the `AuthService` seam; the real implementation replaces one file.
- **The debug menu can flip the payments kill switch** — in DEBUG builds
  only; the entire menu is compiled out of Release.
- **Pinning placeholders** ship in the reference pin set; a real
  deployment must generate pins from its keys before first release.

## Release security checklist

- [ ] `Scripts/secret-scan.sh` passes.
- [ ] Release binary contains no `StubURLProtocol` symbol.
- [ ] Release Info.plist has **no** `NSAppTransportSecurity` entries.
- [ ] Pin set contains the active key AND an offline backup key.
- [ ] `flags.json` state reviewed (kill switch ON).
- [ ] No `print`/`NSLog` outside DEBUG; loggers carry no PII.
- [ ] Full test suite green.
