# RV.92 - two backend log-privacy tests fail in a worktree, and one of them is a real race

`BlobEndpointTests.BlobFlow_NoPresignedUrlOrSecretReachesALog` and
`AuthEndpointTests.NoTokenIdTokenOrEmail_ReachesAnyLogLine` fail in a git worktree and pass in the
main checkout. Measured 2026-09-06: both fail at `/Users/sbelyaev/repos/fc-rv86` in isolation, both
pass on `main` in isolation, and the branch still fails with `main`'s import files swapped in - so
the cause is not the row that found it.

**I have found the auth half, and it is not a worktree property at all.**

## The auth failure: an unlocked enumeration in the test

`InMemoryLogWriter` (`backend/tests/Tankbook.Api.Tests/Logging/LoggingTestHelpers.cs:19-44`) is
correctly locked: `WriteLine` appends under `_gate`, and the `Lines` property returns a **copy**
under the same lock. The test then bypasses both:

```csharp
var lines = new List<string>();          // AuthEndpointTests.cs:339 - the test's own reference
var writer = new InMemoryLogWriter(lines);
...
var all = string.Join('\n', writer.Lines);   // :356 - SAFE, a locked snapshot
Assert.Contains(lines, l => l.Contains("auth.session", ...));   // :359 - UNLOCKED enumeration
Assert.Contains(lines, l => l.Contains("auth.refresh", ...));   // :360 - UNLOCKED enumeration
```

`Assert.Contains(lines, ...)` enumerates the **raw `List<string>`** while the host's pipeline may
still be writing to it from another thread - which is exactly
`Collection was modified; enumeration operation may not execute`, the error the row reports. It is a
**latent race in the test, present in every checkout**, that surfaces when timing shifts; a worktree
run (cold build, cold caches, different contention) shifts timing. That is why it looks
worktree-specific and is not.

`BlobEndpointTests.cs:424-426` has the **same three unlocked `Assert.Contains(lines, ...)` calls**.

**Fix**: enumerate the locked snapshot everywhere - take `var captured = writer.Lines;` once and
assert against `captured` (and build `all` from the same snapshot, so both assertions describe the
same instant). Do **not** "fix" it by sleeping, retrying, or widening the lock into the test.

## The blob failure: a framework line reaching the sink

The other half is different and is **not** explained above: the assertion that fails is
`Assert.DoesNotContain("presign.invalid", all, ...)` (`BlobEndpointTests.cs:432`), and the offending
line is ASP.NET's own `"Redirecting to https://presign.invalid/..."` - the framework's redirect
logger, not our `blob.get` line. So the question is **why that framework category reaches the writer
in a worktree and not in the main checkout**, and the answer is almost certainly **configuration
resolved by path**.

Check, in this order, and report what you find rather than fixing the first plausible thing:

1. **Log-level filtering.** Find where the test host configures `Logging:LogLevel` (appsettings, an
   `ILoggingBuilder` call, or the test's `StartAsync`). If `Microsoft.AspNetCore.*` is filtered to
   `Warning` in one tree and not the other, that is the whole story.
2. **Content root / configuration path.** A `WebApplicationFactory`-style host resolves its content
   root from the entry assembly's location or a repo-root walk. **A worktree's `.git` is a FILE, not
   a directory** - anything walking up looking for a repo root can stop somewhere else, load a
   different (or no) appsettings, and get different log levels. Grep for a repo-root walk in the test
   host and in `DocPaths` if one exists.
3. **Testcontainers reuse across trees**, only if 1 and 2 come back clean.

**The honest fix depends on what you find**, and there are two acceptable shapes: make the host's
logging configuration explicit in the test (so no tree's file layout can change it), or make the
privacy assertion examine **our** log lines rather than everything the sink received. Prefer the
first - the second narrows a privacy check, and this suite exists to catch a secret reaching **any**
log line (hard rule 12). If you choose the second, say why the narrowing is safe.

## Why this row matters even though it blocks nothing

**A worktree that lies makes a verified row unverifiable.** A real regression found there would be
dismissed as "the worktree thing", which is precisely how a genuine defect gets shipped. The
deliverable is an explanation plus a fix, never "it is flaky".

## Tests

Backend row: `cd backend && dotnet build`, `dotnet test`, `dotnet format --verify-no-changes`. Report
counts before -> after (it was 410).

- **L2**: both named tests pass **in a fresh worktree** and in the main checkout. Give the exact
  commands you ran in each tree and the exit codes. Create the worktree yourself under
  `/tmp` (NOT inside the repo), and **remove it when you are done** - an orphaned worktree leaves
  DerivedData behind (2.2 GB was reclaimed from two of them on 2026-09-06).
- **L1/L2**: the race fix is proven, not asserted - run the two tests repeatedly (say 50x) in the
  tree where they failed and report zero failures. A single green run proves nothing about a race.

### Vacuous traps, named

- **Re-running until it passes.**
- **Deleting the worktree instead of explaining it.**
- Calling the tests "flaky" without showing **what differs** between the two runs - the row rejects
  that answer explicitly.
- Fixing only the auth test: the blob test has the same unlocked enumeration AND a second, different
  cause. Both need naming.
- Asserting the redactor is correct (it is - `TankbookRedactor.cs` is byte-identical across the
  trees, already verified).

### Mutations (run each, report, restore byte-for-byte)

1. Put the unlocked `Assert.Contains(lines, ...)` back -> under repeated runs the race must return
   (report the failure rate you observe; if it does not return in 50 runs, say so - that is
   information, and it means the fix's proof needs a different shape).
2. Whatever made the framework line stop reaching the sink, undo it -> the blob assertion must fail.

## Explicitly out of scope

- The iOS redaction sweep (`RV.91` - different tier, different mechanism).
- Changing `TankbookRedactor` or any privacy class.
- Removing `"presign.invalid"` from the assertion.
- Adopting worktrees as a workflow - `CLAUDE.md` says work in the checkout; this row explains a
  failure, it does not endorse the tool.

## Docs to reconcile

`docs/TESTING.md` if the finding changes what a worktree run can be trusted to prove - that is
exactly the kind of thing the "Which gates for which change" section exists to record.

## Hard rules that decide things in this area

**12** (never log a domain value, a token or a presigned URL - what these two tests guard) ·
**14** (it builds and it lints: for this row `dotnet build` + `dotnet format --verify-no-changes`).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, and the docs named in this brief. **If your row's "out of
scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been four times this month, and the agent was right every
time. If the reproduction does not match what this brief claims, **say so and report what you
measured**; that is a better outcome than a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after).
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `dotnet build` -> 0, `dotnet test` -> 0 (count before -> after),
  `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  Run `xcodegen generate` first if you added a file. **Check the observed count is non-zero.**
- **A change touching a `#if DEBUG` seam also builds RELEASE**
  (`xcodebuild -configuration Release ... build`).
- **`$?` after a pipe is the pipe's exit code.** Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The reproduction: what you measured BEFORE changing anything, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. What is now true that was not before. If the honest answer for some case is "nothing changed",
   say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
