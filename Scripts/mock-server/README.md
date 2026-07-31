# Local mock server

A real HTTP server for exercising the app's URLSession path
(`RemoteLoanRepository` / `RemotePaymentRepository`) end to end.

## Run it

```sh
npx json-server db.json --port 3000
```

## Point the app at it

Either:

- **Launch argument** (Xcode scheme → Arguments):
  `-loanpay-environment remoteLocalhost`
- **Debug menu** (triple-tap the "My Loans" title) → Environment →
  Localhost server, then relaunch the app.

The in-process mock remains the default; the remote path is opt-in per
launch.

## What to know

- `db.json` mirrors the bundled fixture dataset (25 loans, 3 payment
  methods). Edits to it show up on the next request — no rebuild.
- json-server is a *dumb* server on purpose: no auth check, no server-side
  paging, no idempotency dedupe. The app still sends `Authorization`,
  `X-Correlation-ID` and `Idempotency-Key` on every relevant request —
  watch them with the server's log output. Submitted payments append to
  the `payments` array in `db.json`, so replay behavior is inspectable.
- Cleartext HTTP to localhost is allowed by a DEBUG-ONLY ATS exception
  (`SupportingFiles/Info-Debug.plist`). The Release Info.plist has no ATS
  exceptions — verified in the release audit.
