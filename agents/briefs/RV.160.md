# RV.160 - sending feedback looks like nothing happened

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-09: *"after feedback sent, there is no confirmation that the feedback was
sent."*

A confirmation technically exists and cannot do its job:

- `FeedbackComposerView.statusText` (`:183-190`) renders every outcome at `.font(.caption)` in
  `Theme.Palette.inkSoft` - **the same muted treatment as the disclaimers around it**, and the same
  as `footnote` directly below.
- It sits **below the Send button**, at the bottom of a composer that is inline inside the About
  `ScrollView` (`AboutView.swift:31`), so on a small screen it is plausibly **below the fold at the
  moment of the tap**.
- **The loudest visible change is the form emptying.** `FeedbackModel.send()` clears `text` and
  `replyTo` on `.sent` (`FeedbackModel.swift:76-77`), which reads as *"my message vanished"*, not
  *"it was sent"*.

Nothing resets the state, so the line is not disappearing - it is simply not noticeable, which for
a confirmation is the same defect.

**[RV.132] already settled the pattern for this exact shape**: a user-initiated action that
completes gets a toast; automatic work stays silent (S8). The rate demand drain speaks. Sending
feedback - rarer, more deliberate, and irreversible from the user's side - does not.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. Two things I could not settle from a grep, and you must:

1. **`toastCenter` is NOT currently in scope in `AboutView` or `FeedbackComposerView`** - I looked
   and found no `@Environment(AppToastCenter.self)` in either. The mechanism reaches other surfaces
   through `AppRates.onDemandToast`, a static closure wired once at `TabRoots.swift:173`. **Work out
   what the right reach is here** and say why: an environment value, the existing static-closure
   idiom, or something local to the sheet. **Do not add a second toast mechanism** - one is the
   point.
2. **Whether a toast is even visible over this surface.** About is presented from Settings; if the
   toast host does not cover a presented sheet, a toast is the wrong answer and an in-place
   confirmation the user cannot miss is the right one. **Check before building, and report what you
   found.** If the toast cannot be seen, say so and solve the row a different way rather than
   shipping a confirmation that is invisible for a new reason.

## What to build

**Acknowledge the send where the user is looking.** Hard rule 7 makes every error name its next
step; a success the user cannot see is the same failure of legibility from the other direction.

**Cover all four outcomes, not just `.sent`.** `FeedbackModel.State` distinguishes `sent`,
`queuedOffline`, `queuedRateLimited`, `queuedRetry` - and **a queued case is not a failure**. The
message is safely stored and will go. Saying so is the difference between trust and a user
re-sending the same report three times. `consentRequired` is a fifth state and is already `warn`
coloured; it is a refusal, not an outcome - leave its meaning alone, but make sure your change does
not make it quieter.

**Decide what the screen becomes after a send, and record the decision.** Note the asymmetry
already in the code: `.sent` clears `text` and `replyTo`, the three queued cases do **not**.
Clearing the fields while leaving the form open is what makes a success read as a loss. Whether the
composer collapses, resets, or stays put is yours to settle - but settle it deliberately, write it
in `docs/ERRORS.md`, and make the queued/sent behaviours consistent with the reason you give.

Any new string is EN and RU (hard rule 10), one full localised phrase per language - never
composed. RU runs 20-30% longer and this is a toast.

## Explicitly out of scope

- **[RV.159]** - the two look-alike consent toggles on this same screen. A separate row, and it
  touches the same file: **do not restyle the toggles**, and if your change makes their treatment
  worse or better, say so in your report.
- The outbox, the retry policy, the rate limiter, `docs/API.md`'s feedback contract. This row is
  about what the user sees, not when anything happens.
- `deviceModelToggle` and the diagnostics preview.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> **Home** (the [RV.132] toast precedent and its wording rules) and the About /
   feedback rows. This doc is the authority for every user-facing message; extend it in the same
   change with what each of the four outcomes now says.
2. `docs/DESIGN.md` -> the toast treatment and hard rule 5 (amber is attention only; a success is
   not amber, and red appears only inside system dialogs).
3. `CLAUDE.md` hard rules 7, 10, 12.

## Environment axes this crosses

**Locale** - new strings, EN and RU, localization gate at 100%. **Offline** - `queuedOffline` is one
of the four outcomes and is reachable with the network off; say how you exercised it (the
`-feedbackTransportOffline` and `-feedbackRateLimit` launch arguments exist). **Screenshots: EN and
RU are required.** No signed-out difference (feedback needs no account). **Release**: only if you
touch a `#if DEBUG` seam - note that `-feedbackAutoSend` (`FeedbackModel`) is one, so if you extend
that seed you must also run `xcodebuild -configuration Release ... build`.

## If this adds a failure path, what makes it visible in production?

It should not add one - this is presentation over states that already exist. If you find yourself
adding a branch that can silently do nothing, add the shape-only event that would let one device
log answer "did the user get the confirmation?" (`docs/LOGGING.md`, hard rule 12: no message text,
no reply-to address, no domain values). Say explicitly whether you added one and why.

## Tests you must add

- **L4, and it FAILS TODAY**: sending feedback surfaces a confirmation the test finds **without
  scrolling**. **Oracle**: the confirmation's frame is inside the window's visible bounds after the
  Send tap. **Assert the frame against the window, never `isHittable`** - [RV.84] measured
  `isHittable` returning `true` for an element **86% clipped**, which is exactly this failure mode.
- **L4**: each of the four outcomes says something **distinct**, and the queued ones do not read as
  failures. **Oracle**: `FeedbackModel.State`'s four cases and the strings `docs/ERRORS.md` gives
  each; assert the localization **key** per outcome, not the English text.
- **L1**: the state transitions are unchanged. **Oracle**: `FeedbackModel.send()`'s existing switch -
  `.sent` / `.queued(.offline)` / `.queued(.rateLimited)` / `.queued(.serverError)` /
  `.consentRequired`. This row changes what the user sees, not when.
- **L1**: the existing default-OFF consent tests stay green - you must not change what gates a send.

Name the UI suite you extend and report its observed, **non-zero** test count.

## The mutation you must run - I am naming it, do not choose your own

**Move the confirmation back below the Send button in its old muted `inkSoft` caption treatment**
(or, if you built a toast, delete the presentation call and leave the state transition intact). The
new L4 test **must go red on the visibility assertion**, not on an existence assertion. Then restore
and re-run. Report both outputs verbatim.

That mutation is the row's headline claim: the state was always correct and the user still could not
see it, so the test has to fail on *seeing*, not on *existing*.

## Vacuous traps, named

- **Restyling the caption and calling it a confirmation** - it is still below the Send button in a
  scroll view. If you keep it in place, the test must prove it is on screen at the moment of the tap.
- **Asserting the status text EXISTS rather than that it is visible** - it exists today; that test
  passes on the unfixed code.
- Treating a queued outcome as an error.
- Adding a toast and leaving the emptied form still reading as a loss.
- Asserting English text instead of the localization key.
- A composed string ("%@ sent") - RU word order breaks it, which `P1.4` already proved.

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
right.

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count -
   a filter matching nothing prints "0 tests … passed" and still exits 0. Several suites are
   `extension` of another suite's class, so a class-name filter can match nothing.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; what you found about
toast reach over the About surface and which mechanism you chose and why; your decision on what the
composer becomes after a send; whether your change affected [RV.159]'s toggles; and **anything you
found and did not fix**.
