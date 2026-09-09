# RV.159 - two consents look identical and only one of them gates sending

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-09: *"the current feedback screen now has 2 toggles - attach diagnostic data
(and look at) and 'help improve' toggle. They look the same."*

Three switches sit on the About screen, and **two of them are pixel-identical**:

| Control | File | Treatment |
|---|---|---|
| "Attach diagnostics" | `DiagnosticsSection.swift:17-23` | `.caption.weight(.semibold)` · `Theme.Palette.ink` · `.tint(taillight)` |
| `feedbackConsent` - *"Help improve scanning - attach this case"* | `FeedbackComposerView.swift:112-124` | **the same three modifiers** |
| `feedbackAttachDeviceModel` | `FeedbackComposerView.swift:85-93` | `.caption` · `inkSoft` · `.tint(taillight)` |

**They are not the same kind of thing, and the difference matters:**

- **Diagnostics** attaches Tankbook's **own** log, sync result and entry counts, is **previewable
  before sending** (*"Preview what will be shared"*, the `previewRow` that appears when it is on),
  and carries **no user content**.
- **The improve-scanning consent** attaches **the user's case**, is a standing opt-in, and **gates
  the send**: without it `FeedbackModel.send()` sets `.consentRequired` and the outbox refuses to
  queue. The blocking message reads *"Turn on 'Help improve scanning - attach this case' to send"* -
  **which a user who has just enabled "Attach diagnostics" has every reason to believe they already
  did.**

This is a **consent-comprehension defect, not a styling one**. `docs/SECURITY.md` and hard rule 13's
spirit both rest on the user understanding what they agreed to, and two identical switches whose
consequences differ cannot carry that.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left, and **`RV.160` may have shipped into
`FeedbackComposerView.swift` before you** - it is the row directly ahead of this one and it touches
the same file. **Re-read the file first.** If RV.160 changed the composer's layout or what happens
after a send, build on what you find rather than on this brief's line numbers, and say what moved.

## What to build

**Make the two visibly different kinds of control, and make the gating one legible as a gate.**

They differ on three axes worth showing:

1. **What leaves the device** - our log vs the user's own case.
2. **Whether it can be previewed** - diagnostics can, the case cannot.
3. **Whether it blocks sending** - only the consent does.

**Decide the treatment and record it in `docs/DESIGN.md`.** The obvious moves are grouping them
under separate headed sections (`SectionEyebrow` already exists and `StationSettingsView` uses that
idiom), giving the gating consent the weight of a **requirement** rather than an option, and
reworking the copy so both do not open with *"attach"*. **The choice is yours - write down which you
made and why**, because the next person needs the rule, not the diff.

**The blocking message must name the control the user is looking at, in the words on the switch.**
If you reword the consent's label, the refusal message must move with it, or you have made the dead
end worse.

**Walk the send-blocked path end to end.** Today a user can write feedback, tick the wrong toggle,
press Send and be refused - a dead end whose next step is buried in a caption below the button
(hard rule 7). Note that `RV.160` is about the *success* side of this same surface; **do not fight
it** - if it landed first, the refusal should use whatever mechanism it established.

Both strings are EN and RU (hard rule 10), one full localised phrase per language, never composed.
**RU is where a longer label collides with a switch** - a `Toggle`'s label gets the width the switch
leaves it, and Russian runs 20-30% longer.

## Explicitly out of scope

- **[RV.160]** - the missing send confirmation. It is the row ahead of this one in the same file.
- The outbox, the rate limiter, `docs/API.md`'s feedback contract, and what diagnostics actually
  collects.
- The diagnostics **preview sheet** itself (`OB.4`) - you may point at it, not rebuild it.

## Docs to read before writing (in order)

1. `docs/SECURITY.md` -> what each consent covers and what leaves the device. **This is the
   authority for what you are allowed to say each switch does** - do not paraphrase from the code.
2. `docs/ERRORS.md` -> the About / feedback rows, including the consent-required refusal.
3. `docs/DESIGN.md` -> section and control treatment; hard rule 5 (amber is attention only, red only
   inside system dialogs - a consent is neither).
4. `CLAUDE.md` hard rules 7, 10, 13.

Extend `docs/DESIGN.md` in the same change with the rule you chose, and `docs/ERRORS.md` if the
refusal's wording changes.

## Environment axes this crosses

**Locale** - EN and RU, localization gate at 100%. **Largest Dynamic Type** - a two-line label
beside a switch is the failure shape here; exercise it
(`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL` is already used by `P6.10`).
**Screenshots: EN and RU required**, and at XL if that is where your treatment is tightest. No
Release seam expected, no offline path, no signed-out difference.

## If this adds a failure path, what makes it visible in production?

It should not - this is presentation over existing state. If you add a branch that can silently do
nothing, add the shape-only event that answers "did the user hit the consent refusal?"
(`docs/LOGGING.md`, hard rule 12 - never the message text, never a reply-to address). Say whether
one already exists on the `.consentRequired` path.

## Tests you must add

- **L4, and it FAILS TODAY**: the two consents are **distinguishable by more than their label**.
  **Assert the distinguishing property you introduced** - a section header, a different control
  type, a different container - not that both toggles exist. **Oracle**: the three axes above; the
  property you assert must be the one a user would use to tell them apart.
- **L4**: with **only "Attach diagnostics"** on, Send is refused **and the message names the
  improve-scanning switch in the words on that switch**. **Oracle**: `FeedbackModel.send()`'s
  `guard hasConsented else { state = .consentRequired }` - diagnostics consent is a different
  property and must not satisfy it.
- **L4**: with **only the improve-scanning consent** on, Send succeeds and **no diagnostics ride
  along**. **Oracle**: `FeedbackPayload` carries `deviceModel` only when its own toggle is on; the
  diagnostics attachment is a separate path entirely.
- **L1**: **neither consent defaults ON.** The existing default-OFF tests must stay green - find
  them and say which they are. A consent that arrives pre-agreed is a security defect, not a
  usability one.
- **L4**: EN and RU at the largest text size.

Name the UI suite you extend and report its observed, **non-zero** test count.

## The mutation you must run - I am naming it, do not choose your own

**Restore the gating consent's original three modifiers** (`.caption.weight(.semibold)`,
`Theme.Palette.ink`, `.tint(Theme.Palette.taillight)`) and remove whatever container or header you
added, so it is once again visually identical to "Attach diagnostics" - while leaving the gating
logic untouched. **The distinguishability test must go red.** Then restore and re-run. Report both
outputs verbatim.

That is the row's headline claim: the logic was always right and the user still could not tell the
two apart, so the test must fail on *telling them apart*, not on behaviour.

## Vacuous traps, named

- **Asserting both toggles exist** - they both exist today; that passes on the unfixed code.
- Changing only the copy, so the two controls remain the same object in a different sentence. Copy
  alone can be a legitimate answer, but then the test must assert the *comprehension* property, and
  you must argue why a user reading quickly will not conflate them.
- Making the gating consent **amber or red** to signal importance - hard rule 5 forbids both.
- Rewording the switch and leaving the refusal message quoting the old words.
- Defaulting either consent to ON to "simplify" the flow.
- Testing at the default text size only, where a one-line label hides the collision.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

An "RU" screenshot was once English with Russian dates. It passes an md5-difference check and is
still wrong. **You cannot see your own screenshots**: state what you captured, never that it looks
right. **Check what is BEHIND your subject too** - a correct control photographed over an
impossible screen is a capture that looks successful and proves nothing.

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count -
   a filter matching nothing prints "0 tests … passed" and still exits 0. Several suites are
   `extension`s of another class, so a class-name filter can match nothing.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; the treatment you chose
and the rule you wrote into `docs/DESIGN.md`; whether [RV.160] had already changed the file and what
you built on; what the refusal message now says; and **anything you found and did not fix**.
