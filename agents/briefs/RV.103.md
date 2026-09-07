# RV.103 - the Log stops at 20 rows and there is no way to see the rest

## The defect, measured

The **Log tab IS Home** (`AppTabBar.case log = 0`), and Home's list is a **preview**:
`HomeLogSection` renders `stream.previewRows(Self.previewLimit)` with
**`previewLimit = 20`** (`ios/App/Sources/Home/HomeSections.swift:308,315`). The list ends after the
20th row. **There is no "See all", no pagination, no load-more and no date filter** - grep
`ios/App/Sources/` and confirm before you build.

The type's own comment says it is *"the Home preview, not the full Log stream screen (P1.6)"* -
**no full-stream screen exists**, so that sentence describes a door that was never built.

**The cost, on the owner's real data**: [RV.93] imports 513 fill-ups and **493 are unreachable in
the app**. They are in the database, counted in every derived figure (hard rule 2 - the totals are
RIGHT while the rows behind them are invisible), restorable and exportable, and impossible to look
at. A user who imported their history in order to see it cannot. **This is not data loss** - hard
rule 8 is intact - it is a screen that stops where the data does not.

## Decide the shape before building, and say why

Three coherent answers. **Pick one (or the two that compose) and justify it in the report:**

- **(a) Load more.** The preview grows in pages as the user scrolls. Simplest; needs no new screen
  and no artboard.
- **(b) A full-log screen** the preview links to - what the comment and `docs/SCREENMAP.md` imply was
  intended. Needs an artboard, or an explicit "built from Home's own vocabulary" note ([RV.86]'s
  precedent for the `.cars` step).
- **(c) Filter by period** - year, or a date range. **The product owner asked for this explicitly**,
  and it is the only one that answers "what did this car cost me in 2024" without scrolling a decade.

(a) and (c) compose; (b) is the bigger change. **My preference, and say why if you differ: (a) then
(c)** - load-more removes the wall today, the period filter makes a decade navigable, and neither
needs pixels that do not exist yet.

## Fences

- **Stay local and derived.** No query endpoint, ever: hard rule 9 forbids server-side domain queries
  and there is no exception for this. Everything is computed on device from the synced rows.
- **The month dividers must keep agreeing with the rows beneath them.** `LogStream.Section.totalSpend`
  is per-section; a paged or filtered stream must not leave a divider summing rows the user cannot
  see. (**Coordinate with [RV.106]**, which is changing what a divider prints when rows are
  rate-pending - if it has landed, build on it; if not, do not fight it.)
- **A purchase group is never split.** `previewRows` already protects the cut
  (`LogStream.swift:274-283`); the same must hold at every page boundary.
- **Measure the cost, do not assume it.** `LogStream` builds sections over `allRows` and Home
  rebuilds it on every load. **Report the build time on the owner's real volume** (the 513-row
  `Spike/ImportFixtures/mfm/fuel.csv` import) before and after. A 500-row car may be fine and a
  5000-row one may not; the number is the deliverable, not the reassurance.

## Explicitly out of scope

- Redesigning the row card, the month divider's visual, or the anomaly/duplicate cards.
- Search by station or note - that is a different feature and a different row.
- Trends, export, or anything that already sees all the rows.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1**: the page after the first never drops or duplicates a row - assert the union of ids across
  pages equals the whole stream, not just the counts.
- **L1**: a purchase group is **never split across a page boundary**.
- **L1** (if you build the filter): a period filter's month totals equal the sum of the rows it
  shows, and a period with no entries says so rather than rendering an empty month.
- **L4 `HomeUITests`**: a car with **more than 20 entries** offers the affordance, and using it
  reveals a row that was **not on screen before** - assert that specific row, not a count.
- **Perf**: the stream build over 513 rows, timed and reported.

### Vacuous traps, named

- **Raising `previewLimit` to a bigger constant and calling it fixed** - the next history is longer,
  and this row is about the missing **door**, not the number behind it.
- **Asserting the affordance exists** without asserting a previously hidden row becomes visible.
- **Testing with 20 or fewer entries**, where nothing is hidden and every assertion passes today.
- **Asserting a row count rather than which rows** - a page that silently drops an entry counts the
  same as one that does not.

### Mutations (run each, report, restore byte-for-byte)

1. Drop the last row of each page (an off-by-one) -> the union-of-ids test must fail.
2. Split a purchase group at a page boundary -> its test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Screenshots

EN **and** RU, **dark**: `design/screenshots/RV.103-log-more.png` / `-ru.png`, showing the
affordance (and the filter, if you build it) on a car with a long history.
- Seed from the committed MFM fixture so the volume is real.
- Capture outside a test run; **verify the pair differs with `md5 -q`** and report both hashes.
- You cannot see your own screenshots; the orchestrator opens every one.

## Docs to reconcile

`docs/SCREENMAP.md` (the Log's inventory - and the "full Log stream screen" that does not exist
should stop being implied), `docs/JOURNEYS.md` if a journey gains the step, `docs/DESIGN.md` if a new
affordance pattern is introduced.

## Hard rules that decide things in this area

**2** (totals are derived and must agree with what is shown) · **6** (numbers in DIN, `tabular-nums`
where digits align) · **7** (an end-of-list that is not the end of the data must say so) · **9** (no
server-side query, ever) · **10** (EN + RU) · **14**.

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
