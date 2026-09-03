# RV.22 – the sync state chip beside the Settings gear

The product owner, 2026-09-03: *"I don't see in the UI a connection-to-account icon (and a sync
state)."* There is none - a user cannot tell whether their data is in the cloud. This builds it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`** - the orchestrator ticks the row after verifying; an agent editing
it silently un-ticks other tasks when the conflict is resolved by side. Touch no `backend/` file.

**Use the `iPhone 17` simulator for every xcodebuild/xcrun step.** Another agent may be using
`iPhone 17 Pro` concurrently and `simctl`/`xcodebuild` fight over a shared device.

## This is PRESENTATION, not a new state machine

The state model already exists and is L1-tested - **building a second one beside it is the main way
this task goes wrong**:

- `SyncSurfaceState` (`ios/Sources/TankbookCore/Sync/SyncSurface.swift`) carries `isSignedIn`,
  `offline`, `serverUnavailable`, `authExpired`, `deviceRevoked`, `quotaUsedPercent`, `dirtyCount`,
  `flaggedCount`, `isSyncing`, `lowPowerModeDeferring`.
- `SyncSurface.status()` has a documented precedence and `SyncStatus.isAttention` its own meaning.
- `AppSync` is `@Observable` and already publishes `surfaceState`.
- `SyncSurfaceTests` is the L1 model to follow for anything you add.

## The design, settled by the product owner - build exactly this

One SF Symbols family, so the chip reads as **one object changing state**, and every state has a
distinct **silhouette**: colour makes it findable, it never carries the meaning alone.

Precedence, in order - the first match wins:

| # | Condition | Glyph | Colour | Label EN / RU | Tap |
|---|---|---|---|---|---|
| 1 | `!isSignedIn` | `icloud.slash` | `inkSoft` | "Not signed in" / "Не выполнен вход" | Sign in |
| 2 | `deviceRevoked` / `authExpired` / `quota >= 95` | `exclamationmark.icloud` | **`warn`** | "Device signed out" / "Устройство отключено" · "Sign in again" / "Войдите снова" · "Storage full" / "Хранилище заполнено" | Settings, scrolled to the card naming the fix |
| 3 | `isSyncing` | system `ProgressView(.circular)` | **`action`** | "Syncing…" / "Синхронизация…" | Settings |
| 4 | `dirtyCount > 0` | `icloud.and.arrow.up` | **`inkSoft`** | "Waiting to sync · N changes" / "Ожидают отправки: N" | Settings |
| 5 | otherwise | `checkmark.icloud` | **`ok`** (new token) | "Synced" / "Синхронизировано" | Settings |

Four things about that table are decisions, not preferences:

- **State 1 is deliberately colourless.** Staying local is legitimate (hard rule 1); a hue would
  read as a fault. It is also the only state that leaves Settings as its destination.
- **State 2 is the only amber the chip can ever show** (hard rule 5: amber is attention only).
- **State 4 is never amber**, because a week of queue looks exactly like an hour of queue.
- **`offline` is NOT a state.** `isOfflineWithQueue` deliberately shows ordinary SYNCED reassurance
  when offline with nothing to push, because *"offline is never an error"* (`docs/SYNC.md`). Offline
  and 5xx are **label variants of state 4**, never a promotion to warning. Do not promote offline to
  make the chip tidier.

**`flaggedCount > 0` is not a sixth state.** A `warn` dot rides the chip's corner over whatever
state is showing, and taps to **Log filtered to flagged entries** (`docs/ERRORS.md:192`) - never
Settings. Hard rule 8 keeps conflict badges where the data lives; a global "sync issues" screen is
what that rule forbids.

### The colour correction you must NOT undo (product owner, 2026-09-03)

An earlier revision of this design said `headlight` for states 3 and 4. **That was wrong and is
now settled as `action` / `inkSoft` above.** `docs/DESIGN.md` P6.7 reserves `headlight` for
*genuinely electric things only* - enforced by `PaletteAccentGuardTests`' allowlist - and names
`action` as the colour for *"app-initiated activity the user is watching (progress bars)"* and
`inkSoft` for *"status badges"*. **Do not add a sync-chip entry to the electric allowlist**, and do
not "fix" the chip back to `headlight`: that permanently loosens what `headlight` means.

### The new `ok` token

Add `ok` = **`#4FD18C` dark / `#0E7A46` light** to `design/tokens.json` (which generates
`Theme.generated.swift`) and document it in `docs/DESIGN.md`'s colour table - **never as a literal
in a view** (hard rule 5).

**Both values are proposals until measured.** They must clear **4.5:1 on `midnight` AND `dash`, in
BOTH themes**, checked by `PaletteAccentGuardTests` - extend that suite to cover `ok` exactly as it
covers `action` and `headlight`. **A green that fails the guard is a rule-5 violation and the guard
is the only thing that catches it** - XCUITest cannot read colour, which is precisely how P1.1
shipped an accent-red tab bar while its suite stayed green. If a value fails, report the measured
ratio and stop - do not silently pick a different green.

## The gap this chip exposes - resolve it explicitly and write it down

**`SyncSurface.status()` never consults `isSignedIn`**, so a signed-out device computes `.synced`
today. State 1 above needs that answered. Choose one and say which in your report:

- `status()` grows a `signedOut` case, **with its L1 tests** and the precedence documented; or
- the chip resolves sign-in *before* asking for a status.

Either is defensible; papering over it is not. Whichever you choose goes in `docs/SYNC.md` beside
the existing surface documentation.

## Placement

`ios/App/Sources/Navigation/TabRootHeader.swift` is the shared one-row header all three tab roots
use since RV.21 (title + Settings gear on one line), so the chip lands there once and appears on
Log, Trends and Garage alike. Confirm that before assuming it.

## Read before writing

1. **`CLAUDE.md`** - hard rules 5 (palette tokens, amber is attention only, accent is meaning), 7
   (every error names its next step), 8 (conflicts are badges where data lives), 10 (String
   Catalogs, whole phrases per language), 12 (counts and state names are loggable, domain values
   never), 14.
2. `docs/DESIGN.md` - the colour table, the **P6.7 `action` rule**, the accessibility floor
   ("colour is never the only channel").
3. `docs/SYNC.md` → the Settings sync surface; `docs/ERRORS.md` → Settings and line 192.
4. `ios/Sources/TankbookCore/Sync/SyncSurface.swift` + `SyncSurfaceTests.swift`,
   `ios/App/Sources/Settings/AppSync.swift`, `ios/App/Sources/Navigation/TabRootHeader.swift`,
   `ios/Tests/TankbookCoreTests/PaletteAccentGuardTests.swift`.

## Tests

- `cd ios && swift build ; swift test` - **1189 today; must not fall.**
- **L1** for any mapping you add to `SyncSurface` (state → chip presentation). `SyncSurfaceTests` is
  the model. If you add a `signedOut` case, its precedence gets tests too.
- **L1** in `PaletteAccentGuardTests` for the `ok` token's contrast on both grounds in both themes.
- **L4**: each state renders its own chip; the chip is hittable; **its tap destination differs by
  state** (sign-in vs Settings vs the flagged-entry Log). Assert the **accessibility labels**, never
  the hues - XCUITest cannot read colour. The in-flight state uses the system `ProgressView` and
  degrades to a still glyph under Reduce Motion (the RV.8 precedent).

**Vacuous-assertion traps, named:**
- Asserting the chip `.exists`. It exists in every state; that tests nothing.
- Asserting a label is non-empty rather than asserting *which* state it names.
- Testing only the `.synced` state - the four that need attention are the ones users hit.
- A tap test that asserts "a screen appeared" without asserting **which** - three states have three
  different destinations and that routing is half the feature.

**Mutation-check and report it**: break the precedence so `authExpired` no longer outranks
`dirtyCount`, confirm the L1 test goes red, restore byte-for-byte and confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** Zero lint **errors**.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24.

## Screenshots - one per state, EN and RU

`design/screenshots/RV.22-chip-<state>.png` and `-ru.png`, dark theme, taken **outside** any test
run (`simctl` and `xcodebuild test` fight over the device). Add the capture lines to
`scripts/capture-screenshots.sh`, and seed each state so the shot actually shows it - a shot of
`.synced` five times proves nothing.

**RU is the real test here**: "Ожидают отправки: N" and "Устройство отключено" are far longer than
their English counterparts, and a chip label is exactly where that overflows. Russian runs 20-30%
longer and short strings expand worst.

You have no image input, so say so plainly - the orchestrator opens every shot personally.

## Report back

- Exit codes, test counts before/after, suites RUN, the mutation result.
- **The measured contrast ratios for `ok`**, both grounds, both themes - numbers, not "it passed".
- **Which way you resolved the `isSignedIn` gap**, and where you documented it.
- Confirmation that no sync-chip use was added to the electric allowlist.
- Files changed, docs extended, anything unfinished - named plainly.
