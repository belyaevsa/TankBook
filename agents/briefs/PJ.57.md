# PJ.57 - the excluded-entries footnote is a link that renders exactly like a caption

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect, pinned to a line

`ios/App/Sources/Shared/ExcludedEntriesFootnote.swift:22-42`:

```swift
var body: some View {
    Group {
        if let destination {
            NavigationLink(value: destination) { label }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.localize("Shows the excluded entries"))
                .accessibilityIdentifier(identifier + "Button")
        } else {
            label                       // ← the SAME view
        }
    }
}

private var label: some View {
    Text(L10n.entriesExcluded(count))
        .font(.caption2)
        .foregroundStyle(Theme.Palette.warn)
        .accessibilityIdentifier(identifier)
}
```

**Both branches render the identical `label`.** A tappable footnote and an untappable one are
**byte-identical on screen**: same font, same colour, no chevron, no other cue. The only difference
is an accessibility hint, which a sighted user never receives.

`design/screenshots/RV.141-home-excluded.png` shows the consequence: "2 entries excluded" sits in
amber directly below a blue affordance and reads as a label. [RV.141] shipped the destination and
the explanation - **both hold, the journeys walk confirmed it** - so this is the last step of that
journey and it is the one a user has to guess.

**Colour cannot be the fix.** Amber is correct here: hard rule 5 makes amber *attention*, never
*action*, and recolouring it blue would break the rule the footnote currently obeys. That is exactly
why the affordance has to be something other than colour.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Confirm both branches still render the same view**
before changing anything, and **find every caller** - `HomeSections.swift:399-401` passes a
`destination`, and other callers may pass `nil` deliberately. A caller relying on the passive
rendering must keep it.

## What to build

**Give the link a non-colour affordance, and keep the passive case passive.**

`GarageView.swift:377-381` is the precedent and the vocabulary to reuse:

```swift
private var chevron: some View {
    Image(systemName: "chevron.right")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.Palette.inkSoft)
}
```

That is the chevron [RV.83] added to the Garage attention strip for this exact reason. **Reuse the
same glyph and weight** so "this row leads somewhere" has one vocabulary in the app - if it belongs
in a shared place rather than copied, move it there and say so.

**The two branches must become visibly different.** That is the actual defect: not that the link is
hard to see, but that it is indistinguishable from the thing that does nothing. Do not make the
passive case look tappable to "keep them consistent".

**Do not recolour.** Amber stays (hard rule 5). If your treatment needs the chevron in a different
tone than `inkSoft` to be legible beside amber text, say why.

**Record the rule in `docs/DESIGN.md`**: an amber footnote that leads somewhere carries the chevron;
amber never becomes the action colour. Written down, the next amber link does not repeat this.

## Explicitly out of scope

- **[RV.159]** - the two look-alike consents. Same comprehension class, different screen, its own
  row. Cite it if your rule generalises; do not touch that file.
- **[RV.141]**'s destination and its explanation - both shipped and both hold. This row is the
  affordance only.
- Every other amber caption in the app. If you find one that is also a link, **report it** - that is
  a finding, and it is a row.

## Docs to read before writing (in order)

1. `docs/DESIGN.md` -> the palette semantics (hard rule 5) and the row/affordance conventions
   [RV.83] added. **This is the authority**; extend it in the same change.
2. `docs/ERRORS.md` -> the Home excluded-entries row, so the copy and its next step stay what they
   are.
3. `CLAUDE.md` hard rules 5 and 7.

## Environment axes this crosses

**Locale** - no new string expected, but **RU is where the count phrase plus a chevron is tightest**
("2 записи исключены" plus a glyph on one caption line). **Screenshots: EN and RU required.**
Largest Dynamic Type is worth a look for the same reason. No Release seam, no offline, no
signed-out difference.

## If this adds a failure path, what makes it visible in production?

It adds none - this is a rendering change over an existing branch. Say so in your report rather than
adding a log line.

## Tests you must add

- **L4, and it FAILS TODAY**: the link case is **distinguishable from the passive case by an
  asserted property**. **Oracle**: the two branches of `ExcludedEntriesFootnote.body` - today they
  render the same `label`, so any property that separates them is one that did not exist before.
  **Assert the distinguishing element**, not that the footnote exists or is tappable.
- **L4**: the passive case (`destination == nil`) still renders **without** the affordance. A fix
  that puts a chevron on both is the same defect with an extra glyph.
- **L4**: EN and RU, and assert the row does not truncate with the chevron present - RU is the
  case that breaks.
- **L1 or L4**: the existing RV.141 behaviour is unchanged - the tap still reaches the excluded
  entries. Find the existing test and say which it is; do not duplicate it.

Name the UI suite you extend and report its observed, **non-zero** test count.
`ExcludedEntriesUITests` exists (`ios/App/UITests/ExcludedEntriesUITests.swift`) and uses
`-seedHomeExcludedMix`; `-homeScrollToExcludedFootnote` parks Home on the footnote for a capture.

## The mutation you must run - I am naming it, do not choose your own

**Delete the affordance you added from the `NavigationLink` branch**, so both branches render the
same `label` again - leaving the navigation itself working. **The distinguishability test must go
red.** Then restore and re-run. Report both outputs verbatim.

That is the row's headline claim: the link always worked and the user could not tell it was one, so
the test has to fail on *telling*, not on *navigating*.

## Vacuous traps, named

- **Asserting the footnote is tappable** - it already is; that test passes on the unfixed code.
- **Recolouring it to blue or the accent** - breaks hard rule 5, which is the rule the current code
  gets right.
- Adding the chevron to **both** branches, which restores the identity this row exists to break.
- Asserting `isHittable` - [RV.84] measured it returning `true` for an element **86% clipped**.
  Assert the frame against the window.
- Testing EN only, where the count phrase is short enough that the chevron always fits.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is behind your subject** - the footnote lives below the fold, so a capture without
`-homeScrollToExcludedFootnote` photographs the top of Home and proves nothing. `RV.149`'s first
capture put a correct toast over an impossible screen for exactly this reason.

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; whether you moved the
chevron to a shared place and why; every other amber caption you found that is also a link; and
**anything you found and did not fix**.
