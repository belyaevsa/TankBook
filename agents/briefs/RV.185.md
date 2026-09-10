# RV.185 - a car created by an import ignores the declared currency and cannot be named

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. **Agents never tick `docs/TASKS.md` and never commit.** An agent ticked its own row on
2026-09-10 and the orchestrator reverted it.

## The defect

Product owner, 2026-09-10, importing a Drivvo export: *"I picked to create a new car, but I wasn't
able to set the name of the car - I got default 'drivvo'. My currency I chose during the import was
KZT, but after import to a new car the currency became EUR."*

### Half one - the currency, and this is the serious half

`TargetCar.newCar(named:)` (`ios/App/Sources/Import/ImportService.swift:142-153`):

```swift
static func newCar(named name: String) -> TargetCar {
    ...
    homeCurrency: .eur,          // ← hardcoded
```

The user's answer is held in `ImportFlowModel.effectiveCurrency`
(`ImportFlowModel+Wizard.swift:79-82`) and **is** passed to `ImportConversion` for the **entries**
(`:236`, `+Cars.swift:133`) - but never to the `Vehicle` the import creates.

**The consequence is not cosmetic.** The rows land as KZT against a EUR home, so every imported
entry becomes a foreign-currency entry needing a KZT→EUR rate **for its own date**. A clean import
becomes a log full of rate-pending rows ([RV.140], [RV.152], the F9 state) for a user who never
asked for a second currency. Hard rule 13 - *a value the user set is theirs* - is broken at the
moment the value is stated.

### Half two - the name

Two paths create a car, and **neither offers a field**:

| Path | Site | Name it uses |
|---|---|---|
| Single-car | `ImportFlowModel.swift:301`, `:320` | `newCarName` (`:323-327`) - the file's `Vehicle name` column, else **`pickedFormat?.displayName`** (literally `"Drivvo"`), else a localized fallback |
| Multi-car gate | `ImportFlowModel+Cars.swift:76-80` | `Self.newVehicleName(for: group)` |

The multi-car one even documents the omission: *"named from the file (the group's own name, editable
later in the Garage - hard rule 13)"*. **That reads the rule as satisfied by "editable later", and
it is not**: hard rule 13 requires a derived value be editable **at the moment it is offered** *and*
again afterwards. Only the second half holds today.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Reproduce both halves first** - import a fixture
declaring a non-EUR currency into a new car and observe the stored `homeCurrency` and name. Four of
the orchestrator's diagnoses were wrong in one session and an agent caught every one. If the
currency reaches the car by some path I did not find, say so and stop.

## What to build

**Pass the declared currency into the new car.** It becomes a **parameter** of `newCar(named:)`, not
a default - a factory that can silently produce the wrong home currency is what caused this. Both
call sites must supply it.

**Let the user name the car where it is offered**, on both paths: an editable field pre-filled with
today's derived value, so the derivation stays a suggestion rather than a fact. Pre-fill from the
same source as now; the file's own `Vehicle name` is a good guess and `"Drivvo"` is not, so **say in
your report whether the format-display-name fallback should survive at all** once a field exists.

**Do NOT touch the entry conversion** - it already honours the declared currency, and that half
works.

**Do NOT re-home an EXISTING destination car.** Importing into a car the user already owns must
leave its `homeCurrency` alone; that is [RV.152]'s territory and a different decision.

## Check the neighbours and report - do not guess

The same factory hardcodes `units: km / L / L-per-100`, `paceLimitKmPerDay: 1500`, `powertrain:
.ice` and `fuelKinds: [.petrol95]`. A KZT importer is unlikely to be the only user who wanted
something else. **Report** whether the import knows better for any of these (the parse may carry
units - `docs/SCHEMA.md` → Import mapping), and file nothing; a second row is cheaper than a wrong
guess baked into a factory.

## Explicitly out of scope

- `ImportConversion`'s per-entry currency handling.
- [RV.152]'s home-currency change prompt and its conversion.
- [RV.116]'s unsupported-column notice (shipped today, same screen).
- The duplicate/merge counting on the mapping gate.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` → **Vehicle** (what a car must carry) and **Import mapping (launch importers)** -
   what the parse actually knows about a source car.
2. `docs/ERRORS.md` → **Import**, the mapping-gate and preview rows - the authority for what that
   screen says; extend it if the name field changes what is promised.
3. `docs/JOURNEYS.md` → **J2**, the import journey.
4. `CLAUDE.md` hard rules 3 (money is a pair, rate snapshots), 13 (editable **when offered** and
   again after), 10.

## Environment axes this crosses

**Locale** - a new field label and any placeholder, EN and RU, gate at 100%. **Screenshots: EN and
RU** of the gate carrying the name field. **Offline**: unchanged (parsing already needs the network,
rule 1's bounded exception). Release build if you touch a `#if DEBUG` seam.

**Add capture lines to `scripts/capture-screenshots.sh` for any screenshot you commit.** Three rows
shipped out-of-band screenshots in the last day ([RV.176]); a committed frame no line reproduces is a
defect, not an artefact.

## If this adds a failure path, what makes it visible in production?

None expected - this passes a value that already exists into a record that already exists. If you
add a branch where the currency can still be absent, that branch needs the shape-only event that
says so (`docs/LOGGING.md`; a currency **code** is shape, an amount is not - hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: a car created by an import carries the **declared** currency. **The
  fixture's declared currency must NOT be EUR** - with EUR the hardcode and the fix are
  indistinguishable and the test passes on the defect. Assert the **stored** `homeCurrency`.
- **L1**: the car and its imported entries agree, so no imported row is rate-pending *purely because
  of the car's home currency*. **Oracle**: the same `MoneyBackfillService` pending count the F9
  footnote uses - not a count written in the test.
- **L4**: the gate offers an editable name pre-filled with the derived value, and **a typed name
  reaches the saved car** - assert the stored `Vehicle.name`, not that a field exists.
- **L1**: importing into an **existing** car leaves that car's `homeCurrency` byte-identical.
- **L4**: EN and RU.

Name each suite and report its observed, **non-zero** count. **Run app-target suites separately and
check the COUNT** - on 2026-09-10 a filter matched nothing three times and printed `TEST SUCCEEDED`
with exit 0 on **zero tests**; one suite was an `extension` in a differently-named file, so filter by
the **suite** name, not the file's.

## The mutation you must run - I am naming it, do not choose your own

**Restore `homeCurrency: .eur` in the factory**, leaving the entry conversion and the name field
intact. The currency L1 **must go red naming the wrong currency**, and the name L4 must stay
**green**. Then restore and re-run. Report both outputs verbatim.

That split matters: it shows the currency assertion is about the car's stored value, not about the
import succeeding.

## Vacuous traps, named

- **A fixture declaring EUR** - the headline trap; the hardcode and the fix look identical.
- Asserting the name field **exists** rather than that a typed name is **saved**.
- Fixing the car and leaving the entries, or the reverse.
- **Re-homing an existing destination car** - a different decision, and it would break [RV.152].
- Guessing units or a pace limit into the factory instead of reporting.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source** - it reuses the previous binary, and on 2026-09-10
that photographed a mutated build and presented it as proof of the fix.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1864 tests / 222
suites**, **829** localization keys at 100% RU, backend **451**.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target** - `swift build` compiles only the SwiftPM package,
   and every file above is in `ios/App/Sources` ([RV.174]).
5. `xcodegen generate`, then each UI suite you touched **by suite name**, with observed **non-zero**
   counts.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **how you reproduced
both halves before fixing**; your verdict on the format-display-name fallback and on the hardcoded
units / pace limit; and **anything you found and did not fix**.
