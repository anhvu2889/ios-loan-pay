# Releasing LoanPay

## The rules

1. **main is always releasable.** Every merge lands green (CI: build, full
   test suite, lint, secret scan, release audit). If main is red, fixing it
   outranks all feature work.
2. **Features merge small and daily, behind flags.** Incomplete work ships
   dark (`flags.json` off) rather than living on long branches. The
   `search_enabled` flag is the worked example: the code merged across
   several PRs while the flag gated exposure.
3. **Releases are short-lived `release/<version>` branches** cut from main
   on a schedule (the "train leaves on time" model). After the cut, ONLY
   cherry-picks **from main** may land on the branch — a fix that isn't on
   main first doesn't exist. No feature work on release branches, ever.
4. **Flag state at cut decides contents.** The train carries whatever main
   had, exposed exactly as `flags.json` said at cut time. Turning a feature
   on for a release = one flag commit on main before the cut, not a code
   scramble.
5. **Every cut is snapshotted**: `Scripts/release-snapshot.sh <version>`
   tags the SHA and writes `Releases/<version>-manifest.json` (SHA + full
   flag state) — "what exactly did 1.4.0 ship?" is a file, not an
   archaeology project.

## Two-train timeline

```
main      ──A──B──C──D──E──F──G──H──I──J──▶   (small daily merges, flags gating)
                    │                 │
cut 1.4.0           ├─ release/1.4.0  │
                    │   └──D'(pick E)─┤─▶ App Store 1.4.0
cut 1.5.0           │                 ├─ release/1.5.0
                    │                 │   └────────────▶ App Store 1.5.0
                    ▼                 ▼
              snapshot 1.4.0     snapshot 1.5.0
              (SHA=D, flags@D)   (SHA=I, flags@I)
```

While 1.4.0 stabilizes (cherry-pick E, a crash fix, from main), main never
stops taking features for 1.5.0. Nobody waits for a release to finish to
keep merging.

## Contrast with versioned multi-repo

One trunk + flags + cherry-picked release branches replaces the multi-repo
world's version-matrix bookkeeping (app 1.4 needs SDK 2.7 needs Core 3.1…)
with a single question: "what SHA is the train on?"

## Cutting a release

```sh
git checkout main && git pull
git checkout -b release/1.4.0
Scripts/release-snapshot.sh 1.4.0
git push origin release/1.4.0 v1.4.0
```

Then: run the release security checklist in SECURITY.md, archive, submit.
Fixes: land on main → `git cherry-pick <sha>` onto the release branch.
