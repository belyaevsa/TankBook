# RV.47 – tapping a field's label must focus its input

The product owner, 2026-09-04: *"a user can click on a field name, such as 'odometer', and expects
that the input field will be activated. Today the user must click on an empty field, which is not
obvious."*

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**Use the `iPhone 17` simulator** for xcodebuild/xcrun steps; check `pgrep -x opencode` first and
say in your report whether another agent was running.

**Never move, rename or delete a file you did not create.** A second session works in this checkout.
On 2026-09-04 an agent moved another session's uncommitted migration out of the repo to clean its
baseline - 56 KB of unsaved work. If something in the tree breaks your gate and is not yours,
**report it and carry on**. A currently-known example: `CorpusScorerFuelKindCurrencyTests` may be red
from in-flight corpus fixtures. Not yours.

## The cause, verified - three things compounding in ONE shared component

`FieldRow` (`ios/App/Sources/AddVehicle/AddVehicleComponents.swift:78`):

1. **The row is inert.** It is a plain `HStack` - label `Text`, `Spacer`, value - with **no
   `contentShape`, no tap gesture and no focus binding**. The label and the wide gap beside it
   swallow taps.
2. **The input collapses when empty.** The fields are `TextField("", text:)` with
   `.multilineTextAlignment(.trailing)` and **no placeholder**, so an empty field is a
   near-zero-width hit target pinned to the right edge - far under the **44 pt** floor
   `docs/DESIGN.md` sets.
3. **The underline that would show the field's extent renders only when focused or warning**
   (`fieldUnderline`, same file). So in the empty, unfocused state there is *nothing on screen*
   telling the user where to tap.

**The affordance is invisible precisely in the state where the user needs it.** That is why this is
filed as **hard rule 15** and not polish: typing is a peer entry path, and *"any screen that makes
manual entry harder to reach than capture is a bug"* - a field the user cannot find is exactly that,
on the busiest screen in the app.

**Precedent**: RV.10 made the whole date-row header the tap target with `.contentShape(Rectangle())`
for the same reason. This is that fix, applied to the input rows.

## What to build

**The whole row focuses its field** - label and gap included, the `<label for>` behaviour users
expect.

`FieldRow` is a generic value container today, so it needs the focus target passed in. **That is a
real signature change across EIGHT call sites** - `ManualFillUpSections`, `ManualFillUpFuelCard`,
`EditEntryRows`, `EditEntryNonFillView`, `AddVehicleControls`, `VehicleDetailSections`,
`VehicleFormControls`, `VehicleUnitsEditor`. **Do it once, properly, rather than patching the screen
in the report.** One fix should land on Confirm, Edit entry, Add car and Vehicle detail together.

**Two things it must NOT do:**

- **Rows with no editable field must not become fake buttons.** A value row that opens a picker
  already has its own tap behaviour (RV.10's date row), and a read-only row must stay inert.
  **State in your report how you told them apart** - a type-level distinction beats a per-call-site
  flag someone will forget.
- **Do not change what the fields contain, format or validate.** This row is about reaching them.

## The decision to make explicitly

**Consider giving an empty field a visible extent** - a persistent hairline underline, or the
placeholder these fields deliberately omit. A 44 pt row that focuses on tap still leaves the user
guessing *where the value goes* until they tap.

**If you take it, it is a `docs/DESIGN.md` change**, so make it deliberately and write it down - do
not drift into it. If you leave it, say why. Either is defensible; an unstated choice is not.

## Read before writing

1. **`CLAUDE.md`** - hard rules 15 (two doors, manual entry is a peer), 6 (numbers in DIN, units
   subordinate), 10, 14.
2. `docs/DESIGN.md` - the accessibility floor (**tap targets >= 44 pt**, colour never the only
   channel) and the form-row conventions.
3. `ios/App/Sources/AddVehicle/AddVehicleComponents.swift` (`FieldRow`, `fieldUnderline`),
   `ios/App/Sources/ConfirmManual/ManualFillUpSections.swift` (`odometerRow` and the number rows,
   `ManualFillUpFocus`), and the other six call sites.

## Tests

- `cd ios && swift build ; swift test` - **1242 today; must not fall.**
- **L4 asserts BEHAVIOUR, not existence** - this is the whole bug:
  - **tap the label text and assert the field is focused** (the keyboard is up and the caret is in
    that field), for a **numeric** row and a **text** row;
  - **tap the gap between label and value** and assert the same;
  - assert a **read-only / picker row is unaffected** - it must not steal focus or become a button;
  - **assert the row's hit height is >= 44 pt.** The accessibility floor is the measurable half of
    this bug, and a frame assertion is the only thing that catches a regression to a collapsed row.
- Cover at least two screens (Confirm and Edit entry), because the point of fixing `FieldRow` is
  that it lands everywhere - a test on one screen does not prove that.

**Vacuous-assertion traps, named:**
- Asserting the label `.exists`. It always existed; it was never tappable.
- Asserting the field can be focused **programmatically** - that already worked. The bug is the
  TAP.
- Testing only a row that already had a value, where the input is wide and was always hittable. The
  broken case is the **empty** field.

**Mutation-check and report it**: remove the row's `contentShape`/tap handling and confirm the
tap-the-label test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. Run swiftlint from the **repo root** - from `ios/` its
root-relative `excluded:` paths report thousands of phantom violations. Match the process NAME
(`pgrep -x xcodebuild`); **never `pgrep -f`/`pkill -f`**.

## Screenshots

Only if you add a visible affordance (the empty-field extent above). If you do:
`design/screenshots/RV.47-*.png` and `-ru.png`, dark, outside any test run, capture lines appended
to `scripts/capture-screenshots.sh`. If nothing visible changed, say "none applies" rather than
fabricating one. You have no image input; say so.

## Report back

- Exit codes (captured, not piped), test counts before/after, suites RUN, the mutation result.
- **How you distinguished focusable rows from picker/read-only rows**, and why that distinction
  cannot be forgotten at a future call site.
- **Whether you gave empty fields a visible extent**, and the reasoning either way.
- Confirmation all eight call sites compile against the new signature and that no screen lost
  behaviour.
- The measured row hit height.
- Files changed, docs extended, anything unfinished.
