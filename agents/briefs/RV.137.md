# RV.137 - the catalogue picker is absent when editing a car

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## What was reported

Product owner, 2026-09-08: *"Car model picker (select) stopped working ... in case I tried to edit
the model."*

It did not stop - **it was never on that screen.** `AddVehicleCatalogArea` and `CatalogSuggester`
(`ios/App/Sources/AddVehicle/AddVehicleSections.swift:23,56`) render the suggestion list as the user
types, and are referenced **only** by the Add flow. `VehicleDetailView.swift` contains **zero**
references to either; its make/model/year row (`ios/App/Sources/Shared/VehicleFormControls.swift:162-178`)
is a bare `TextField` whose `onChange` runs `MakeModelParser.parse`, a best-effort string split.

## Read this before you design anything: my first filing of this row was WRONG

I originally wrote that the screen "silently drops the `catalogId` the Add flow captured" and that
the missing picker breaks hard rule 13. **Both are false**, and building on either would break the
screen on purpose:

- **There is no `catalogId` on `Vehicle` at all**, and nothing in the app sets one.
- `VehicleDetailView`'s own header (`:9-18`) states the design: *"A user's edit is theirs
  permanently: **nothing here stores a catalog id for a later pack to rewrite**"*. Not storing an id
  is the **mechanism** that makes an edit permanent, not an oversight.
- Hard rule 13 requires the value to be editable "again afterwards", and it **is** - as text. The
  rule does not require re-offering the picker.

So the defect is narrower than the row first claimed: **the convenience is missing, not the
capability.** A user who mistypes on Add must retype by hand, with no suggestions, forever.

## Design questions ALREADY CLOSED

1. **A pick sets TEXT and stores NOTHING.** Choosing a suggestion fills make, model and year exactly
   as typing them would, and records no id, no link, no catalogue reference. This preserves the
   permanence decision above, which is not yours to reverse.
2. **Reuse `CatalogSuggester` and `AddVehicleCatalogArea`.** Do not grow a second suggester -
   "two implementations of one decision" is precisely what [RV.129] is about. If the Add-flow view
   is too coupled to reuse directly, extract the shared piece rather than copying it, and say so.
3. **The catalogue is bundled and will not be empty.** `VehicleCatalogStore.bundledEntries()`
   (`ios/Sources/TankbookCore/Catalog/VehicleCatalog.swift:85`) is what the Add flow loads
   (`AddVehicleView.swift:240`), so suggestions appear on a fresh install regardless of [RV.129]'s
   finding that `VehicleCatalogUpdater` is never instantiated.
4. **If you conclude this should stay absent by design**, that is a legitimate answer: record the
   decision in `docs/SCREENMAP.md` with its reason and stop. Do not build it half-way.

## The second defect, same screenshot - fix it whichever way question 4 goes

The **Save changes** bar is a `safeAreaInset(edge: .bottom)` (`VehicleDetailView.swift:135`) and the
FUEL chip row is clipped behind it when the keyboard is up, so the user cannot see the chip they are
selecting. **[RV.84] fixed this exact class** on the import parse-error card: that region does
**not** scroll, so content beneath it is *unreachable*, not merely below the fold. Move the content
or the bar - do not simply add padding and hope.

## Explicitly out of scope

- The Add-vehicle flow's own behaviour.
- `MakeModelParser` itself.
- Introducing any catalogue identifier onto `Vehicle` (closed decision 1).
- [RV.134]'s baked-in unit strings, which also live on this screen family.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rule 13, and read `VehicleDetailView.swift:9-18` as the recorded decision.
2. `docs/SCREENMAP.md` -> the Vehicle screen.
3. `docs/DESIGN.md` -> the card treatment and the accessibility floor.
4. `docs/SYNC.md` -> Reference data (why a user's edit must never be re-pointed at a catalogue row).

## Checks

Baseline: `main` is green at **1651 tests / 184 suites**, **777** localization keys, `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**. **Re-measure yourself** and report what you observe.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + the UI suites you touched **by name**; report a **non-zero** observed count.
   A filter matching nothing prints "0 tests ... passed" and still exits 0 - check the count, not the
   exit code.
5. Localization gate - 0, 100% RU, report the key count.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L4**: typing a make on the **edit** screen offers suggestions, and picking one sets make, model
  and year.
- **L1**: a pick stores no catalogue identifier - assert against the saved `Vehicle`, so a future
  change that adds one fails here.
- **L4**: with the keyboard up, **every** fuel chip is fully visible. Assert the chip's frame lies
  inside the window - **never `isHittable`**, which [RV.84] measured returning `true` for an element
  ~86% clipped, and which I had to remove from [RV.133] for the same reason.

### Vacuous traps, named

- Building a second suggester instead of reusing the Add flow's.
- Asserting the suggestion list renders without asserting the **pick sets the fields**.
- Introducing a catalogue id so the pick "sticks" - that breaks the permanence decision deliberately.
- Asserting the Save bar exists rather than that the chips are **not underneath it**.
- Adding bottom padding until it looks right on one device, instead of fixing the inset.

## Screenshots

The Vehicle edit screen with suggestions showing **and** the fuel chips clear of the Save bar with
the keyboard up, dark, EN and RU: `design/screenshots/RV.137-vehicle-edit.png` and `-ru.png`.
Pass the reset flag with the seed. RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Take them **outside** a test run, and **OCR your own capture** before reporting it.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**,
whether you built the suggestions or recorded the decision not to (closed question 4) and why, and
how you fixed the Save-bar overlap. Name any closed decision you think is wrong and stop there.
