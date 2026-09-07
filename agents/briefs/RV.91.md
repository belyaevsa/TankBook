# RV.91 - the redaction sweep can cry wolf, and I have found the exact mechanism

## The row's own hypothesis is WRONG - do not spend the run on it

The row guesses that a random UUID in the line collides with a short forbidden digit string. I
checked that arithmetic and it does not explain the failure: the only forbidden value that could
appear inside a hex UUID is `"119486"` (every other short one contains a `.`, which a UUID has not),
and at 6 hex chars over ~81 windows across the three UUIDs that is roughly **1 failure in 200 000
runs**. The test failed once in about sixty. **Do not chase the UUIDs.**

## The real mechanism, read from the code

`LogRenderer.render` puts the **timestamp first**
(`ios/Sources/TankbookCore/Logging/Redactor.swift:148-150`, `:177-180`):

```swift
parts.append(timestamp(line.timestamp))
...
date.ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
```

so every rendered line begins `2026-09-07T01:42:30.123Z`. The sweep
(`ios/Tests/TankbookCoreTests/LoggingTests.swift:110-131`) is a bare `output.contains(value)` over
that whole string, and the forbidden list (`:98-104`) contains **`"42.3"`**.

`42.3` appears in the timestamp whenever the **seconds field is `42` and the first fractional digit
is `3`** - `...:42.3xxZ`. That is `1/60 × 1/10` = **1 run in 600**. That matches "failed once, then
sixty green runs" far better than one in 200 000, and it is **deterministically reproducible**: build
a `LogLine` whose timestamp is any instant at second 42 with milliseconds in 300...399 and the test
fails on the spot.

**Verify this before fixing it.** Construct that timestamp, run the test, and paste the
`leaked value: 42.3` message into your report. If it does **not** reproduce, say so plainly and go
back to measuring - my diagnosis is then wrong and that is a finding, not a failure. (Check the other
forbidden values against the same string while you are there: `"50.1109"` and `"8.6821"` need four
fractional digits and the format emits three, so they cannot collide; `"64.2"` needs a seconds field
of 64, which does not exist. Confirm or correct that.)

## What to fix, and what must NOT change

**The sweep is the point. It stays a sweep.** It exists so that a field added later, by someone who
forgets its privacy class, is caught without anyone updating a list (hard rule 12). Any "fix" that
narrows what it examines defeats it.

Take the smallest correct option and say which you took:

1. **Sweep the field values, not the whole rendered line.** The timestamp, level, category, event
   name, appVersion and platform are framing the renderer generates - they can never carry a domain
   value, and they are what introduces the collision. Sweeping `line.fields` values (plus the event
   name) keeps every field in scope while removing the noise. This is my preference.
2. **Or make the fixture values incapable of colliding** - values no timestamp, UUID or version
   string can contain. Weaker: it fixes this collision and not the next one.

**Do NOT** remove `"42.3"` from the forbidden list, shorten the list, or relax `contains` - that is
the fix that deletes the check the row exists to protect. **Do NOT** stub the timestamp to a fixed
value in the renderer; the renderer is production code and the test's convenience is not its problem.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1**: the sweep still FAILS when a Sensitive or Never value genuinely reaches the output -
  **prove it by mutating the redactor** (make one `.sensitive` field render its value) and showing
  the test goes red. This is the assertion that matters: a sweep that cannot fail is worthless.
- **L1**: the sweep passes with a timestamp at second 42, milliseconds 300-399 - the exact instant
  that fails today. Pin it with an explicit timestamp, not a random one.
- **L1**: the sweep still covers a field the fixture does not name - add a field to the fixture with
  a Sensitive value and show it is examined (the property that stops the list going stale).
- If you can run the test in a loop cheaply, report the count of iterations and that none failed.

### Vacuous traps, named

- **Removing the colliding value from the forbidden list.** That is the fix that hides the bug the
  sweep exists for.
- **Asserting only the fields the fixture names**, which stops the sweep catching a field added
  later.
- Asserting the test passes once - it passes 599 times in 600 today.
- Freezing the timestamp inside the test only, leaving the sweep still reading the framing.

### Mutations (run each, report, restore byte-for-byte)

1. Make one `.sensitive` field render its value in `LogRenderer` -> the sweep must fail.
2. Make one `.never` field survive redaction -> the structural test (`neverValuesAreDropped...`)
   must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Explicitly out of scope

- Changing what the renderer emits in production (the timestamp stays, with fractional seconds).
- The privacy classes themselves, or `docs/LOGGING.md`'s three classes.
- The backend's redactor (`RV.92` is a different row and a different tier).

## Docs to reconcile

`docs/LOGGING.md` only if the test's contract changes in a way the doc states. If nothing there is
now false, say so rather than editing for the sake of it.

## Hard rules that decide things in this area

**12** (never log a domain value - the rule this sweep guards) · **14** (it builds and it lints).

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
