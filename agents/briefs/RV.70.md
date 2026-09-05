# RV.70 – Settings offers "Tankbook Pro" and the tap lands on an empty screen

**A submission blocker, not a cosmetic gap.** Filed 2026-09-05 while answering App Store Connect's
in-app-purchase questions. **The cause is confirmed in code - confirm it still holds, do not
re-derive it.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## The defect, verified

Two reachable entry points push `Route.paywall`:

- `SettingsView.swift:418` - `proCard`, a `NavigationLink(value: Route.paywall)`
- `SettingsView.swift:569` - inside the QUOTA card, `NavigationLink("Tankbook Pro", value: .paywall)`

And `Destinations.swift:40` resolves `.paywall` to `LeafContent()`, which is `Color.clear`
(`:174-176`). **So the user taps a labelled affordance and gets a blank pushed view: a title and
nothing else.**

**Why this blocks submission, and all three reasons matter:**

1. **App Review guideline 2.1** rejects a placeholder screen a reviewer can reach. The Pro card is
   on the Settings root - it will be reached.
2. **The metadata contradicts it.** `docs/STORE-COPY.md` states there is no paid tier in this
   version, and the listing declares **no in-app purchases**. Shipping a Pro entry point contradicts
   what we are submitting alongside it.
3. **It breaks hard rule 7.** The quota card is the surface that tells a user their cloud-reading
   quota is full. Its only offered next step currently leads to a blank screen - an error naming a
   next step that does not exist is worse than one naming none.

**Pro is cut from v1** (P6.16, `docs/STORE.md` §5). The screen is not missing; **the entry point is
early.**

## What to build

**Remove both entry points from the v1 build. Do NOT build a paywall.**

The `Route.paywall` case, its destination and its strings **may stay** if the v2 work wants them -
but **nothing reachable may lead to them**. Say which you removed and which you kept, and why.

**The quota card still needs a real next step.** After the Pro link goes, it must still tell the
user what to do when cloud reading is exhausted. **Decide that copy against `docs/ERRORS.md`, which
names the next step for every error, and update the doc in the same change.** The honest options are
about waiting for the period to reset or continuing with on-device reading and typing - the local
parse still works (hard rule 1; hard rule 15 - typing is a peer door). Pick one, and say why.

**Do NOT answer this with a "coming soon" paywall.** That is monetisation in an error surface, which
hard rule 7 forbids outright, and a reviewer reads it as an unfinished app.

**Check for other reachable paths to `.paywall`** beyond these two - grep the whole app target,
including any deep link, notification route or debug launch hook - and report what you find.

## Read before writing

1. **`CLAUDE.md`** – hard rule 7 (**every error names its next step**, and monetisation appears in
   no error surface except the car-limit sheet, never mid-capture), rule 1, rule 15, rule 10, 14.
2. `docs/ERRORS.md` → the quota rows (this is the authority for the replacement copy);
   `docs/STORE.md` §5 (Pro cut from v1) and §6; `docs/STORE-COPY.md` (the no-paid-tier claim);
   `docs/SCREENMAP.md` → whether the paywall node should be marked planned-not-drawn.
3. `ios/App/Sources/Settings/SettingsView.swift` (`proCard` and the quota card),
   `ios/App/Sources/Navigation/{Routes,Destinations}.swift`,
   and the free-tier car-limit sheet - **that one IS the sanctioned monetisation surface** under
   rule 7 and must not be disturbed.

## Tests

**iOS unit 1421 today; must not fall.** UI suites: `SettingsUITests`, and whichever drives the quota
card.

- **L4: from Settings, NO control anywhere reaches a blank pushed screen.** Assert the Pro card is
  **absent**, not merely disabled - a disabled control is still a reviewer-visible dead affordance.
- **L4: with `.quotaFull` forced, the card renders, names a next step, and every control on it leads
  somewhere with content.** Forcing the state is the point; the card is invisible otherwise.
- L1: the localisation gate stays green after any strings go.
- L4: the free-tier car-limit sheet is unchanged and still reachable (do not over-remove).

**Vacuous-assertion traps, named:**
- Asserting `Route.paywall` is unreachable in code while the card still renders.
- Asserting the card is hidden **without forcing the quota state that shows it** - it is hidden by
  default, so the test would pass against the bug.
- Snapshotting Settings and calling it verified - **the defect is one tap deeper.**
- Asserting a string was deleted rather than that no path reaches a blank screen.

**Mutation-check and report it**: restore one entry point and confirm the no-dead-end test goes red.
Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required, EN and RU, dark: Settings (showing the Pro card GONE) and the forced-quota card with its
new next step.** Save as `design/screenshots/RV.70-settings.png`, `RV.70-quota-card.png` and the
`-ru` pair, captured OUTSIDE a test run.
**Verify each EN/RU pair differs (`md5 -q a.png b.png`) before reporting them** - RV.58 shipped an
"RU" screenshot byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not
take. A `-` prefixed launch argument can PERSIST across relaunches; reinstall between shots if a
state flag sticks. `scripts/capture-screenshots.sh` is OUTSIDE your write area - name the capture
lines in your report instead. You have no image input: say so.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **Which entry points you removed and what you kept**, with the reason for each.
- **The quota card's new next step, in EN and RU**, and the `docs/ERRORS.md` row you wrote it
  against.
- **Every other reachable path to `.paywall`** you found, including deep links and debug hooks.
- Confirmation the free-tier car-limit sheet is untouched.
- Anything you noticed that is not RV.70 - named separately.
