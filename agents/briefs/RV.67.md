# RV.67 – the Add-car model suggestions cannot be scrolled

Reported by the product owner 2026-09-05: *"the app suggests for me the list, but I can't scroll it
to pick up one. The list folds back after model field focus is lost."* **Diagnosed to three
interacting lines – confirm they still hold, do not re-derive them.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** `.claude/worktrees/rv48` belongs to
another session and is not your gate.

**Use the `iPhone 17` simulator.**

## The cause – three lines, each defensible alone

1. **`ios/App/Sources/AddVehicle/AddVehicleSections.swift:25`** renders the list ONLY while focused:
   `} else if focus == .makeModel, !form.makeModel.isEmpty { suggestionsList }`
2. **`ios/App/Sources/AddVehicle/AddVehicleView.swift:24`** puts the whole form in a `ScrollView`.
3. **`ios/App/Sources/AddVehicle/AddVehicleView.swift:51`** sets
   `.scrollDismissesKeyboard(.immediately)`.

So the drag dismisses the keyboard **immediately**, `@FocusState` clears, `focus == .makeModel`
goes false, and **the list unmounts during the gesture that was trying to reach it**. The
`.immediately` is why it fails on the very first drag rather than at the end of one.

**Why scrolling is needed at all:** `CatalogSuggester.suggestions(for:limit: 5)` returns up to five
rows, and with the keyboard raised the lower ones sit under it - so reaching rows 3-5 REQUIRES the
scroll that destroys the list. The suggestion is offered and then made unreachable.

**The rule this breaks is 13**: the catalog pre-fill (tank capacity, fuel kinds, powertrain) is a
default the user is entitled to accept or edit, and **a suggestion that cannot be tapped was never
offered at all.**

**Suspected sibling - verify it rather than assuming:** `suggestionRow`'s `Button` fires `onApply`
(`AddVehicleSections.swift:61-63`). A tap on a row may also lose focus before the tap registers -
the classic focus race. **Check whether tapping a VISIBLE row is reliable or only usually works**,
and say which.

## What to build

**Decouple the list's visibility from FOCUS.** The condition the screen actually wants is "the user
is choosing a model", not "the text field is first responder": keep it mounted while the field has
TEXT and no suggestion has been applied, and dismiss it on apply, on clear, or on an explicit
dismiss. **Say what you chose and why.**

Alternatives to weigh rather than adopt blindly, and say why you rejected the ones you did:
`.scrollDismissesKeyboard(.never)` or `.interactively` fixes the drag but leaves the list tied to
focus, so the tap race survives; a fixed overlay avoids page-scrolling entirely but must not cover
the field being typed into.

**Do not fix it by shortening the list** - fewer rows is a worse suggestion, not a fixed scroll.
**Do not leave the list up after a suggestion is applied**, or the user cannot see what they just
chose.

**Whatever you change must keep the keyboard usable**: the user is typing a model name, so the field
must stay editable while the list is up, and dismissing the keyboard deliberately must still work.

## Read before writing

1. **`CLAUDE.md`** – hard rule 13 (**the app suggests, the user decides** - editable at the moment
   it is offered AND again afterwards), 7, 10, 14.
2. `docs/JOURNEYS.md` → the add-car journey; `docs/SCREENMAP.md` → Add car;
   `docs/DESIGN.md` if you change any treatment.
3. `ios/App/Sources/AddVehicle/AddVehicleSections.swift` (the whole catalog area,
   `suggestionsList`, `suggestionRow`), `AddVehicleView.swift` (the `ScrollView`, the
   `.scrollDismissesKeyboard`, `focus = nil` at `:102`), `AddVehicleComponents.swift:159` (the
   `simultaneousGesture` that sets focus - RV.47's work, do not regress it),
   `AddVehicleForm.swift`, `CatalogSuggester`.

## Tests

**iOS unit 1395 today; must not fall.** Name the UI suites you run; expect `AddVehicleUITests`.

- **The headline L4: type a model, SCROLL the form, and tap the LAST suggestion.** The assertion is
  that the vehicle is created **with that suggestion's pre-filled tank size** - i.e. the row was
  both reachable and applied. Not that a list appeared.
- **L4: tapping a VISIBLE row applies it first time** (pins the suspected focus race).
- **L1: the visibility predicate is derived from text + applied-state, NOT from focus**, so a later
  change cannot quietly re-tie them.
- **L4: after applying, the list is gone and the chosen values are visible AND editable** (hard rule
  13's second half - editable again afterwards).
- L4: RV.47's tap-the-label-to-focus behaviour still works (you are touching the same screen).

**Vacuous-assertion traps, named:**
- **Asserting the list APPEARS.** It already appears - being unreachable is the bug.
- **Tapping the FIRST row**, which needs no scroll and passes today.
- Asserting a suggestion count, or that `suggestionsList` is non-empty.
- Asserting focus state rather than that a vehicle was created with the pre-filled values.

**Mutation-check and report it**: restore the focus-gated condition and confirm the scroll-and-tap
test goes red. Restore byte-for-byte, confirm green.

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

**Required, EN and RU, dark, WITH THE KEYBOARD RAISED and the suggestion list showing** - that is
the state the bug lives in, and a shot without the keyboard proves nothing. Save as
`design/screenshots/RV.67-addcar-suggestions.png` / `-ru.png`, captured OUTSIDE a test run.
**Verify the two files differ (`md5 -q a.png b.png`) before reporting them**: RV.58 shipped an "RU"
screenshot byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not take,
and the agent could not tell. Use `scripts/capture-screenshots.sh`'s mechanism, and note a `-`
prefixed launch argument can PERSIST across relaunches - reinstall between shots if a state flag
sticks. You have no image input: say so, and say what you could not check.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **What condition now governs the list's visibility**, and why you rejected the alternatives.
- **Whether tapping a visible row was ALREADY unreliable** (the suspected focus race) - and what you
  did about it.
- Confirmation the list disappears after applying, and the applied values stay editable.
- Confirmation RV.47's label-tap focus behaviour is unregressed.
- Anything you noticed that is not RV.67 - named separately.
