# RV.13 – the outbound HTTP logs are the inbound noise all over again

Registered as RV.13 in `docs/TASKS.md`, from production logs on 2026-09-02/03.

`RV.3` re-levelled the **inbound** per-request line. The **outbound** `HttpClient` logs were never
touched, and they are worse: **four Information lines per call**, so one `/extract` costs eight.

```
Information: Start processing HTTP request {"Method":"POST"} {Uri}   [event=RequestPipelineStart]
Information: Sending HTTP request {"Method":"POST"} {Uri}            [event=RequestStart]
Information: Received HTTP response headers after 746.5227ms - 200   [event=RequestEnd]
Information: End processing HTTP request after 747.4277ms - 200      [event=RequestPipelineEnd]
```

Note `{Uri}` and `{Method}` rendering as **literal placeholders**, and
`HttpMethod={"Method":"GET"}` as a serialized object. It reads like a broken logger.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Write nothing outside it. **Do not run
`git add` or `git commit`** - the orchestrator verifies independently and commits.

## THE ONE THING NOT TO DO

**Do not make `{Uri}` render.** It looks like a bug and it is not yours to fix: an outbound URI is a
**domain value**, and `CLAUDE.md` hard rule 12 forbids logging those "at any level, in any build".
The placeholder is *accidentally* on the right side of the rule. Supplying the value would be a
privacy regression dressed as a formatting fix - the rate-feed and LLM-gateway URLs say which
provider a user's receipt went to.

The fix is to **stop emitting these lines at Information**, not to improve them.

## The mechanism (confirmed - do not re-derive)

`backend/src/Tankbook.Api/appsettings.template.json` has:

```json
"Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } }
```

`System.Net.Http.HttpClient` is not in that map, so it falls through to `Default: Information`.
The categories are `System.Net.Http.HttpClient.<name>.LogicalHandler` (the Pipeline pair) and
`System.Net.Http.HttpClient.<name>.ClientHandler` (the Start/End pair), where `<name>` is the named
client - this repo registers `apns`, `jwks`, `rates`, plus the default (`Program.cs` lines ~154,
221-223). A prefix entry covers all of them; that is how `Microsoft.AspNetCore` already works.

## What to build

Configure the `System.Net.Http.HttpClient` category prefix to **Warning**, in the committed
**templates** - `appsettings.template.json` and `appsettings.Development.template.json`
(`appsettings.json` is gitignored and generated from them by
`backend/scripts/generate-appsettings.sh`; editing the generated file changes nothing that ships).
Check whether the Testing environment needs the same and say what you found.

**Before you do, confirm this loses nothing.** The question that decides the task: *does anything
depend on those Information lines to know an outbound call failed?* Evidence it does not - the log
already carries the app's own failure line:

```
Warning: Rate feed cis failed for 09/02/2026 / EUR. [Source=cis ... errorCode=internal_error]
```

Verify that for the **other** outbound callers too (APNs, JWKS, the LLM gateway): each should log
its own outcome. **If you find a caller whose only trace of failure is the HttpClient line, say so
in your report and do not silence that one** - name it and leave it. Silencing the only evidence a
call failed is a worse bug than the noise.

## Tests

`backend/tests/Tankbook.Api.Tests/Logging/LevelDisciplineTests.cs` is the home for this and the
model to follow - read it first. It pins the inbound levelling by outcome and was extended for
RV.16 (unmatched routes) on 2026-09-03.

Pin **both halves**, or the next edit collapses them:

1. An outbound call that **succeeds** emits **no Information line** from the
   `System.Net.Http.HttpClient` categories.
2. A **failure** is still visible - the caller's own Warning/Error line survives.

**Mutation-check it**: remove your configuration entry, re-run, and confirm the first test goes red.
Report whether you saw it fail. A test that passes without the fix is not a test for this bug.

**Vacuous-assertion traps, named:**
- Asserting on a logger you constructed in the test rather than on the app's configured filters. The
  bug is in **configuration**, so a test that never exercises the real config cannot catch it, and
  will pass forever regardless.
- Asserting "no Information lines at all" in a window where none would appear anyway. Make the
  outbound call actually happen, and assert the app's own lines are still there - otherwise the test
  passes equally well against a logger that emits nothing at all.
- Asserting the count of log lines dropped. That passes for any change that makes things quieter,
  including deleting the wrong ones.

## Explicitly out of scope

- The inbound `http.request` line (RV.3 and RV.16 own it - both done; do not re-level it).
- The message templates, the renderer, `LogRenderer`, `TankbookRedactor`.
- Any `iOS/` file. This is backend-only.
- Do not touch `backend/src/Tankbook.Api/Logging/TraceCorrelationMiddleware.cs` beyond reading it -
  RV.16 just landed there. You WILL add tests to `LevelDisciplineTests.cs`; that is expected.

## Read before writing

1. **`CLAUDE.md`** - hard rule 12 (never log domain values) and rule 14 (it builds and it lints).
2. `docs/LOGGING.md` - §3 level discipline, and the RV.16 paragraph added 2026-09-03. **Your change
   is a paragraph there in the same voice**: what was noisy, what it cost, what is now quieter, and
   what is deliberately still loud.
3. `docs/TASKS.md` -> the RV.13 row. Mark it `[x]` with a DONE line when it is genuinely done, and
   update the section header's fixed-list.

## The baseline gate (CLAUDE.md rule 14)

    cd backend
    dotnet build Tankbook.slnx --configuration Release ; echo "BUILD=$?"
    dotnet format --verify-no-changes ; echo "FORMAT=$?"
    dotnet test Tankbook.slnx --configuration Release --no-build ; echo "TEST=$?"

**Judge by the exit code you echoed, not by skimming output** - a `0` printed after a pipe is the
pipe's exit code, not the tool's. The suite is **307 tests, 0 skipped** today; both numbers must
hold. A run that prints `Passed!` with tests skipped is a shrunken gate, not a pass - the CI job
fails on skips above a tolerance of 10 for exactly this reason.

Testcontainers needs docker running for the Postgres-backed tests.

If you check whether a build is running, match the process NAME (`pgrep -x dotnet`). **Never
`pgrep -f` or `pkill -f`** on a build/test pattern: an agent's brief is part of its command line, and
on 2026-08-24 exactly that killed another agent 48 minutes into its task.

## No screenshots

Backend-only; nothing visual changed. **Do not fabricate one** - say none applies.

## Report back

- The exit codes you observed for build, format and test - the numbers, not a summary.
- The test count before and after, and the **skipped** count (must be 0).
- The new test names, and whether you saw the first one FAIL with your config entry removed.
- Which config files you changed, and whether Testing needed the same.
- **Any outbound caller whose only failure evidence was the HttpClient line** - named, and left
  alone.
- Anything you could not finish, named plainly. An honest gap is worth more than a green report that
  does not hold.
