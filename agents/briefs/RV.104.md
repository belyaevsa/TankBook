# RV.104 - let the user accept a flagged entry, in a way re-validation respects

## The defect, and why a UI-only fix is undone by the next pull

After importing years of history the timeline flags (`ConflictState.flagged(kind: .order | .pace)`)
land on entries from **past years**. The gap that caused them is unknowable now - a missing fill, a
sold-and-rebought car, an odometer swap nobody remembers - and there is **no way to say "this is
fine, stop asking"**.

Three facts, measured in the source, that compound:

1. **`TimelineValidator.validate` recomputes the flag from the entries alone** -
   `flags.first.map { .flagged(kind: $0.kind, detectedAt: entry.createdAt) } ?? .none`
   (`ios/Sources/TankbookCore/Validation/TimelineValidator.swift:157-159`) - and takes **no dismissal
   input of any kind**.
2. **Nothing in production ever clears a flag.** The only `conflict = .none` assignment in the repo
   is a test seed (`ios/App/Sources/Settings/FlaggedEntriesTestSeed.swift:29`). Verify that with your
   own grep before you start.
3. **Validation re-runs** on sync apply (`Repository+Sync.swift:523`), on import commit
   (`ImportConversion.swift:364`) and on archive import (`Repository+ArchiveImport.swift:296`).

So the only way to clear a flag today is to **edit the odometer or the date until the invariant
holds** - to invent numbers for a year the user cannot remember - and **a fix that merely hides the
row in `FlaggedEntriesView` is undone by the next sync**. That is the "sync issues later" the product
owner named when reporting this, and it is the first vacuous trap below.

**What it costs**: the flagged count can never be driven to zero, so the one signal that means
"something needs your attention" becomes permanent background noise. A warning that is always on is a
warning nobody reads - the premise hard rule 7 rests on.

## What to build

**A stored, synced acceptance that the validator takes as INPUT.** Not a UI filter, not a local-only
flag.

**Two precedents exist in this codebase and must be followed rather than reinvented:**
- `AnomalyDismissal` (`cause`, `reason`, `dismissedAt` - `ios/Sources/TankbookCore/Consumption/AnomalyEngine.swift:52-62`)
  for anomalies;
- `resolvedDuplicateKeys` (`repository.resolvedDuplicateKeys()`) for S2 duplicates.

Read both, and say in your report which one you modelled this on and why.

**Three decisions the row must make and write down:**

1. **What the acceptance is keyed on.** The entry id alone is **wrong**: an accepted 2019 gap must
   not silently keep covering an entry whose odometer the user rewrites in 2027. Key it on something
   that changes when the accepted facts change - and state the rule.
2. **Whether it carries a reason.** The anomaly dismissal does, and a reason is what makes the
   decision readable a year later. Decide; do not default silently.
3. **How it syncs.** It is a domain fact and rides the record's payload - **no server change** (hard
   rule 9). A second device must not re-flag what this device accepted.

**It must be reversible** (hard rule 8: an accepted entry is still flaggable again, and the
acceptance is visible somewhere - never a silent hole in the data), and **per entry, deliberate**.
**No bulk "accept everything the import flagged"** - that would hide the real problems the flag
exists to catch, which is the whole point of the signal.

## Explicitly out of scope

- Changing what `TimelineValidator` **detects** - the `.order` and `.pace` rules are correct.
- The F9a inline fixes on Edit entry, which stay exactly as they are.
- Anomalies and duplicates - they already have their own dismissal paths.
- Any server change.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1, the assertion this whole row turns on**: an accepted entry **survives a re-validation** -
  run `TimelineValidator.validate` again over the same entries and assert the flag does **not** come
  back. An in-memory "it looks cleared" assertion proves nothing.
- **L1**: editing the accepted entry's odometer or date **re-flags it**, per whatever keying you
  decided - state the rule and assert it.
- **L1**: an entry that was never accepted still flags exactly as it does today.
- **L2**: the acceptance survives a sync round-trip and the second device does not re-flag.
- **L4 `FlaggedEntriesUITests`**: accepting from the row drops the count, and the count reaches
  **zero** when the last one is accepted - the state the owner cannot reach today.

### Vacuous traps, named

- **Hiding the row in `FlaggedEntriesView` without touching the validator** - the flag returns on the
  next sync, which IS the defect.
- **Asserting the flag is gone in memory** without re-running validation.
- **Testing acceptance on a freshly created entry** rather than an imported one with a real gap - the
  case the row is about.
- **A bulk accept** that makes every assertion pass and every future warning meaningless.
- Asserting the count fell without asserting it fell for the **right** entry.

### Mutations (run each, report, restore byte-for-byte)

1. Stop feeding acceptances into the validator -> the survives-re-validation test must fail.
2. Ignore the keying when the entry is edited -> the re-flag-on-edit test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Screenshots

EN **and** RU, **dark**: `design/screenshots/RV.104-flagged-accept.png` / `-ru.png`, showing the
affordance on a flagged row (and, if the copy carries a reason, the reason surface).
- Capture outside a test run; **verify the pair differs with `md5 -q`** and report both hashes.
- RU matters: this copy explains a judgement the user is making about their own data - read the
  rendered Russian for sense, not only for overflow.
- You cannot see your own screenshots; the orchestrator opens every one.

## Docs to reconcile

`docs/SCHEMA.md` (the acceptance's shape, its keying rule and that it rides the payload),
`docs/SYNC.md` (what a second device does with it), `docs/ERRORS.md` (the "Needs a look" surface now
has a next step, and the 3-question audit applies), `docs/JOURNEYS.md` if F9a gains the step.

## Hard rules that decide things in this area

**2** (stats are derived - and the flag is derived too, which is exactly why the acceptance must be
an input rather than a stored result someone overwrites) · **7** (a warning that cannot be resolved
stops being read) · **8** (reversible, visible, never a silent hole) · **9** (payload fact, no server
change) · **13** (the app suggests, the user decides - this row IS that rule for the timeline) ·
**10**, **14**.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, `backend/src/**`,
`backend/tests/**`, `design/screenshots/**`, and the docs named in this brief. **If your row's "out
of scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been several times this month, and the agent was right every
time. If what you measure does not match what this brief claims, **say so and report the
measurement**; that beats a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after). Never
  subset it.
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
- **Watch the file-length ceiling**: several files sit at 699-700 lines and the lint error is a hard
  700. If your change pushes one over, split it the way the codebase already does (`+Wizard`,
  `+Cars`, `L10n+…`), never by deleting comments.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The measurement this row asked for, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. Screenshot paths and md5s, if this brief asked for screenshots.
5. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
6. Anything in this brief that was wrong, as a Residual.
7. Whether the tests were actually **run**, not only written.
