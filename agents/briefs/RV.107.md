# RV.107 - the backend PR job runs the tests and never looks at what ran

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

**Another agent is working in this same checkout right now, on iOS Swift files under
`ios/`.** Touch nothing under `ios/`. If `git status` shows modifications there, they are not
yours - leave them alone and do not stage or revert them.

## The defect, pinned

`.github/workflows/backend.yml:65` (the PR job):

```yaml
      - name: Test
        run: dotnet test Tankbook.slnx --configuration Release --no-build
```

No TRX logger, no results inspection. When Testcontainers cannot start PostgreSQL the ~153
database-backed tests report as **skipped**, `dotnet test` still prints `Passed!` and **exits 0**,
and the pull request is green on the half of the suite that needs no database.

**The sibling job already does this correctly.** `.github/workflows/backend.yml:180-215` (deploy)
writes `--logger "trx;LogFileName=results.trx"`, finds the file, parses `<Counters>`, and fails when
`notExecuted` exceeds a tolerance. Read those lines first. **The fix is to give the PR job the gate
its sibling has** - not to invent a second one.

## Closed decisions - do not reopen

1. **The tolerance is 10 and is NOT zero.** The comment at `:190-198` records why: failing on any
   skip at all fired a red deploy on 2026-09-02 over one transient `SkippableFact` while the other
   294 ran. A wholesale skip is ~153; a handful is noise. **Setting it to zero reintroduces a
   defect that was already fixed once.**
2. **`ios.yml` gets NO `xcodebuild test` step.** `docs/UI-TEST-REVIEW.md` files this as a defect;
   the product owner decided against it on 2026-09-07 and `docs/TASKS.md` -> RV.107 records the
   reasoning: iOS has **no CI deployment path** (the app ships to TestFlight locally), so the gate
   is the orchestrator running the suites before each commit. Do not touch `ios.yml`.
3. **Do not restructure the workflows** into reusable/composite actions. Duplication of a ~20-line
   shell block across two jobs in one file is acceptable here; a refactor of the deploy job's
   gate risks the path that actually ships.

## What to build

### A. The PR job asserts what ran

In the PR job only:

- Add `--logger "trx;LogFileName=results.trx"` to the `dotnet test` invocation at `:65`.
- Add an **"Assert the database-backed tests actually ran"** step immediately after it, with the
  same three assertions the deploy job makes: a results file **exists**, the **executed** count is
  **non-zero**, and `notExecuted` is **at or under the tolerance**. Print the counters line either
  way, and emit the `::warning::` for a non-zero skip under tolerance.
- **The deploy job does not currently assert a non-zero executed count** - it reads `executed` and
  never uses it. Add that assertion to **both** jobs: a TRX reporting `executed="0"` is a suite
  that discovered nothing, which is green today in both. Say so in your report.

### B. Report the identity of the skips, not only the count

The deploy job's own comment warns that a numeric tolerance can hide the one case a change broke.
So when `notExecuted > 0`, **print the skipped tests' names** - `grep` the TRX for
`<UnitTestResult ... outcome="NotExecuted" testName="..."` and print up to the first 20, with the
total. This goes in **both** jobs' gate step, because it is the half the deploy job is missing.

Keep it POSIX shell with `set -euo pipefail`, matching the existing step. No new dependency, no
`xmllint`, no Python - the existing step parses with `grep -o` and yours must stay runnable on the
same runner image.

## Explicitly out of scope

- `ios.yml`, any iOS file, any `.slnx` or project file.
- Changing which tests run, or making any test skippable/unskippable.
- The deploy job's tolerance VALUE, its `XUNIT_THREADS`, or its `DOTNET_gcServer` setting.

## Docs to read before writing

1. `docs/TASKS.md` -> the RV.107 row (**the authority for this task** - it carries the product
   owner's decision about `ios.yml`).
2. `docs/TESTING.md` -> "Which gates for which change", and the note RV.92 just added about what a
   worktree backend run can prove.
3. `docs/BACKEND-TEST-REVIEW.md` for the 210-of-386 figure, if you need the context.

## Checks - the gate must be shown to FIRE, not merely to exist

**A workflow-file diff is not evidence.** The row names this as its vacuous trap: "asserting the
workflow file changed rather than that a skipped suite turns the job red". You cannot open a PR, so
prove it locally instead, and show both directions:

1. **The red direction.** Produce a TRX in which the database tests did not run - the honest way is
   to run the suite with the Docker host unreachable:
   `DOCKER_HOST=unix:///nonexistent dotnet test backend/Tankbook.slnx --configuration Release --logger "trx;LogFileName=results.trx"`.
   If that does not produce a wholesale-skip TRX on this machine, **hand-write a TRX fixture** with
   `<Counters ... executed="233" notExecuted="153"/>` and a few `NotExecuted` `UnitTestResult`
   entries. Then run **your gate step's shell body verbatim** against it and show it **exits 1**
   with the count and the names in the message.
2. **The green direction.** Run the same shell body against the **real** TRX from a healthy run and
   show it **exits 0**.
3. **The executed=0 direction.** Run it against a TRX with `executed="0"` and show it exits 1.

Report the **exit code you observed** for each of the three, and the exact error text printed.

Put any fixture TRX and any scratch script in
`/private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/a5918dd1-31c0-421f-be44-490e7cdbfea7/scratchpad/`,
**not in the repo**. The repo gains only the workflow change.

### The ordinary gates

Baseline: backend **411 tests**, `dotnet build` 0, `dotnet format --verify-no-changes` 0.

4. `cd backend && dotnet build` - exit 0.
5. `cd backend && dotnet test` - exit 0, **411 passed**, and report the number you observed.
6. `cd backend && dotnet format --verify-no-changes` - exit 0.
7. **Lint the YAML you changed.** If `actionlint` is on PATH, run it and report the exit code; if
   it is not, say so rather than claiming a check you did not run, and instead confirm the file
   parses with `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/backend.yml'))"`.
8. iOS gates are **not required** - you touch no Swift. Say so rather than skipping silently.

### Vacuous traps, named

- Asserting the workflow file changed rather than that a skipped suite turns the job red.
- Copying the tolerance without the identity reporting - that reproduces the exact hole the deploy
  job's own comment warns about.
- Setting the tolerance to zero.
- Testing only the red direction, so a gate that fails on everything looks correct.
- Claiming `actionlint` ran when it is not installed.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "dotnet.*test"` matches **you** and the other
running agent. Use `pgrep -x dotnet`. Never `pkill -f`.

## Report back

The three gate-firing directions with observed exit codes and printed text, the four ordinary gates
with exit codes, and whether each was **run or only written**. If you find the brief wrong, say so
and stop at that point rather than absorbing it.
