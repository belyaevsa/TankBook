# Tankbook – Design Language

*Companion to `VISION.md`. Defines the visual and interaction style for the iOS app.*

## Direction: the night drive

The identity comes from the road at night: blue-black asphalt, taillight red-orange ahead, headlight cyan sweeping past. Dark is the brand's home theme (the app is mostly opened standing at a pump or a charger); light theme is its overcast-daylight counterpart. Chosen from a four-option palette exploration (Night Forecourt, Deep Petrol, Night Drive, Ledger) – Night Drive won for being the most unmistakably automotive.

One sentence to test every decision against: **the app should feel like a precision instrument, not a finance form.**

## Color

Semantic first: `taillight` and `headlight` are not decoration, they encode powertrain. Everything that burns fuel is taillight red-orange; everything electric is headlight cyan. The EV-vs-petrol household comparison inherits its color coding from this rule for free.

| Token | Dark (home) | Light | Role |
|---|---|---|---|
| `midnight` | `#101318` | `#F5F6F8` | Background (blue-black asphalt / overcast daylight) |
| `dash` | `#1A1F27` | `#FFFFFF` | Cards, sheets |
| `ink` | `#EAEDF2` | `#1A2028` | Primary text |
| `inkSoft` | `#98A2B3` | `#55606E` | Secondary text, captions |
| `taillight` | `#F4503A` | `#D63A26` | Primary accent: fuel entries, hero numbers, main CTA |
| `headlight` | `#4FC3E8` | `#0A6A8C` | Electric: charging entries, kWh metrics |
| `warn` | `#F0A030` | `#B06E10` | Anomalies, failed cross-checks, overdue reminders |
| `action` | `#8FB4D9` | `#2F6690` | Interactive: buttons, links, selection, focus, progress |
| `ok` | `#4FD18C` | `#0E7A46` | Positive reassurance: "Synced", healthy/confirmed states |

Rules:
- One accent per screen region. A fuel card never shows cyan, a charge card never shows taillight.
- **`action` is the interactive colour, not a third accent (P6.7, 2026-08-27).** Both accents encode powertrain, so for most of the UI there was nothing legal to reach for - buttons, links and selected states borrowed `headlight` until this rule existed. `action` marks things the user can act on (button labels, text links, selected/active states, focused-field underlines) and app-initiated activity the user is watching (progress bars, the restore badge). Inert decoration - placeholder glyphs, informational icons, status badges, chevrons - is `inkSoft`, never `action`: `action` is an affordance, not "a blue". `headlight` survives **only** on genuinely electric things (charging entries, kWh metrics, EV powertrain); the app's electric uses are enumerated by an escape-guard test (`PaletteAccentGuardTests`), so every future `headlight` use is a deliberate act, not a habit.
- **`ok` is the positive-status colour, not a fourth accent (RV.22, 2026-09-03).** It marks the reassurance that everything is healthy - the sync chip's "Synced", and any future confirmed/done state - and nothing else. It is a *status badge* token like `inkSoft`, distinguished from `inkSoft` only by valence: `inkSoft` is neutral ("waiting to sync"), `ok` is positive ("synced"). It carries no interactive meaning, so it is never `action`, and it is green only in the "healthy" sense, never as decoration. Both its values must clear 4.5:1 on `midnight` and `dash` in both themes (`PaletteAccentGuardTests`), exactly like every other accent.
- Because the primary accent is a red-orange, **warnings can never be red**: everything "attention needed" (failed cross-check, consumption anomaly, overdue reminder) is `warn` amber, and destructive confirmations use the system's native alert red inside system dialogs only. This is the discipline that separates us from My Fuel Manager, which paints its chrome red and leaves errors nowhere to go.
- `taillight` is meaning, not chrome: navigation bars, backgrounds, and tab bars stay neutral – the accent appears on numbers, entry markers, the capture button, and the cross-check lock, nowhere else.
- No gradients, no glassmorphism on content. Depth comes from elevation and the taillight glow reserved for the signature card.

## Typography

Two voices, split by role:

- **Numbers: DIN.** `DIN Condensed` (large display metrics) and `DIN Alternate Bold` (inline figures). DIN is the typeface of European road signage and license plates, and both ship built into iOS – no licensing, no bundling. Every metric the user cares about – consumption, price, total, odometer – is set in DIN with `tabular` figures. This is the app's most recognizable trait.
- **Everything else: SF Pro** via native text styles, so Dynamic Type, weights, and localization behave like the platform. Labels, buttons, body text never use DIN.

Scale (SwiftUI):

| Role | Face | Style |
|---|---|---|
| Hero metric ("6.8 L/100km") | DIN Condensed | 56pt, tracking −1 |
| Card metric (total, liters) | DIN Alternate Bold | 28pt |
| Inline figures in lists | DIN Alternate Bold | matches `.body` size |
| Screen titles | SF Pro | `.largeTitle` bold |
| Body, labels | SF Pro | `.body` / `.subheadline` |
| Units, eyebrows ("L/100KM", "€/L") | SF Pro | `.caption2`, uppercase, +8% tracking, `inkSoft` |

Units are always typographically subordinate to their number: small, uppercase, soft ink, positioned after the figure. The number is the content; the unit is the caption.

## Signature element: the Pump Card

The scan-confirm card is styled as an echo of the pump readout the user just looked at – the one moment of boldness in an otherwise quiet app.

```
┌──────────────────────────────┐
│  RECEIPT · SHELL · 21:47     │   ← eyebrow, SF caption
│                              │
│   TOTAL          71.02 €    │   ← DIN, amber
│   LITERS         42.30 L    │
│   PRICE/L        1.679 €    │
│   ─────────────── ✓ ────    │   ← the cross-check line
│                              │
│   ODOMETER      [______] km  │   ← the one manual field
│   +907 km since last fill    │   ← live delta, instant typo check
│                              │
│         [ Save fill-up ]     │
└──────────────────────────────┘
```

- The three DIN rows mirror the physical pump's total / volume / unit-price stack – same order, same visual weight.
- **The odometer caption is LIVE (PJ.14, decided 2026-08-30).** The artboard's `+907 km since last fill` is computed from the last-known odometer as the user types, and the four states are decided in core (`OdometerDelta`, L1-tested) so the caption and the save-time `TimelineValidator` flag can never disagree:
  - typed **>** last: `+N km since last` in `inkSoft` – the positive delta.
  - typed **=** last: `Same as last` in `inkSoft` – neutral, never amber. Equal is a legitimate state (no distance driven since the last entry) and it is the pre-fill's own initial state, so amber would alarm on the default screen.
  - typed **<** last: amber `Odometer went backwards – check it.`
  - implied daily pace over `vehicle.paceLimitKmPerDay` (default 1 500 km/day, `docs/SCHEMA.md`): amber `Daily pace over the limit – check it.`
  - Amber is attention, never alarm (hard rule 5); the warn states never block the save – an implausible odometer warns and the user decides (hard rule 13), exactly as `TimelineValidator` flags on save. RU spells out the unit (`+N километров с прошлой заправки`) so the count governs a real one/few/many plural (the 11/21 edge), and the whole caption is one composed phrase per language, never concatenation.
- The **cross-check line** is validation made visible: while `liters × price ≈ total` is unresolved it renders as a thin `inkSoft` rule; when it locks, it fills `taillight` with a tick and a light haptic. If it can't lock, the mismatched field gets a `warn` amber underline and the tap-to-edit affordance – never a modal alert.
- Low-confidence OCR fields render at 60% opacity until confirmed by tap or edit. Confidence is shown, not hidden.

## Consents: a sending gate is never drawn as an optional attachment (RV.159)

One surface can carry two opt-ins a hasty reader will conflate, and conflating them is a
consent-comprehension defect, not a styling one. About is the case that wrote the rule:

- **A gate** – an opt-in whose absence blocks the send. The feedback composer's improve-scanning
  consent: "Send this case to help improve scanning", default OFF; without it Send is refused.
- **An offer** – optional context that never blocks anything. The "Attach diagnostics" card (its
  own preview + share-sheet path) and the "Attach device model" row.

Until RV.159 the gate and the diagnostics offer were drawn as the same object - the identical
toggle treatment, both phrased around "attach" - so a user who enabled "Attach diagnostics" had
every reason to believe they had already agreed to send.

**Rule: a gate and an offer are different kinds of object, and the difference is structural, never
decorative colour.**

- A gate sits in its own section, introduced by a `SectionEyebrow` that names the act it gates
  ("Before you send") - the same headed-section idiom StationSettingsView uses. An offer has no
  section of its own; it stays a quiet row under the section that owns it.
- A gate's label states what it permits in plain words ("send this case") and does not borrow the
  offer's vocabulary ("attach"). The diagnostics card may say "Attach"; the gate may not.
- A gate's weight comes from structure and copy - ordering, a headed section, a plain consequence -
  never from amber or red (hard rule 5: a consent is neither an attention state nor a danger).
- The refusal that names a gate as the next step quotes the gate in the words on its control, and
  when the control's copy changes the refusal changes in the same change: RV.159's dead end was a
  refusal a user could not match to a switch they had already looked at.

## Motion

Three orchestrated moments; nothing else animates beyond system defaults.

1. **Digit roll:** hero metrics change with an odometer-style vertical roll (per-digit, 250ms, spring). Used on the dashboard when a new entry lands.
2. **Cross-check lock:** the rule draws in from both ends toward the tick, paired with `.success` haptic.
3. **Capture handoff:** the receipt photo shrinks into the Pump Card, which flips up from it – camera and card feel like one object.

All three degrade to crossfades under Reduce Motion.

## Layout & navigation

- **Tab bar:** Log · **Capture** · Trends · Garage. Capture is a raised `taillight` circle, center, always one thumb-tap from anywhere – the app's front door.
  - **[v2] amendment (decided 2026-08-29, `docs/AGENT.md` §3): the bar gains a fifth slot for the Car Agent – `Log · Trends · ● Capture · Ask · Garage`.** Ask is glyph-and-label like the others, never raised, never accented (accent is meaning, not chrome). It sits right of the capture circle so the two most-used actions – capture and ask – are under the thumb together. The fifth slot is for *Ask*, not for Settings: the rule below that keeps Settings off the bar stands. Everyone sees the tab (a tab that appears only after paying reads as a rug-pull); free users open it to the examples and the Pro card. Geometry unchanged: 56pt circle, 22pt raise, 10/12/28 padding; five slots at `min-width: 56px` fit 390pt with the circle's own slot, and must be verified at 375pt. **RU label `Спросить` (8 chars vs `Ask`) is the P6.13 shape – verify at Dynamic Type XL; `Чат` is the fallback.** Artboards, in `design/screens/v2/`: `AgentHome.dc.html` (the bar in context), `AgentAltHeader.dc.html` (the rejected header-button alternative, kept for the record).
  - **The bar is owned, not the system's (P2.1b).** `TabView` stays as the state engine (it preserves each tab's `NavigationStack` for free), but its bar is hidden (`.toolbar(.hidden, for: .tabBar)`) and replaced by a bespoke `AppTabBar` attached with `.safeAreaInset(edge: .bottom)`. The artboard always described a bespoke bar – a full-width `#0D1015` row with a 1px `#1C222C` top border – which is neither iOS 26's floating pill nor iOS 18's translucent material. Two attempts to reuse the system bar failed: iOS 26 renders it as a pill that is not a findable `UITabBar` (so an overlaid circle could not be positioned), and a real `.tabItem` renders its glyph as a template (no filled circle, shadow or raise). Owning the bar also switches off the whole iOS 26 behaviour set (floating pill, scroll-edge effects, `tabBarMinimizeBehavior`), so it is static and identical on iOS 18 and iOS 26. The bar's geometry is the artboard's own: 56pt capture circle, 22pt raise, 10/12/28 padding; the background and border are `tabBar` / `tabBarBorder` tokens.
  - **Deliberate deviation – tab-label type.** The artboard freezes tab labels at 10px, which fails accessibility review. The labels use a Dynamic Type-capable font capped at `.accessibility1` with `lineLimit(1)` and a `minimumScaleFactor`, so the bar grows vertically rather than wrapping or truncating. What is lost: exact pixel fidelity to the artboard's 10px labels at default size. What is gained: a bar that passes accessibility review and does not clip under larger type.
- **Home (chosen: Garage-first)** leads with the car card – photo, name, odometer, three vitals – a reminder surface, and the log stream: the full reverse-chronological stream of all entry types (fuel, charge, service), distinguished by accent color and leading glyph. The Log tab IS Home, so the stream lives HERE, not behind an "All entries" screen that was never built (RV.103): it opens with the newest whole months covering ~20 rows and grows in whole-month pages past a "Show N older entries" row at the seam. Monthly dividers carry the month's total spend in DIN.
- **The tab-root header is ONE row, shared by all three roots (decided 2026-08-23 for Home, extended to Trends and Garage by RV.21).** Screen title on the left, **settings gear on the same line** on the right, drawn by the shared `TabRootHeader` on Log, Trends and Garage alike - the three are peer tab roots (`SCREENMAP.md` "Tab roots (no back)"), so no one of them may own the door to Settings, and a gear that sat in a different place per tab would read as a bug rather than a door. The car chip stays on the row below, paired with the capture affordance: those two are actions on *this* car, while the title and gear are the screen's own chrome, and mixing the two reads as a toolbar rather than a header. Not a stacked iOS large title with the gear floating in a nav bar above it: that spends a whole row on chrome before any of the user's data appears, and on a screen whose job is "your car, at a glance" the first thing visible should be the car.
  - Implementation note: this means a **custom header row**, not `.navigationTitle` + `.toolbar` – SwiftUI's large-title layout puts toolbar items on the bar *above* the title by construction, which is exactly the stacking being rejected here. An inline title would also work but loses the type scale. The three roots draw the identical row and hide the navigation bar, so the gear's position is pixel-identical on each (the RV.21 frame-match UI test enforces it).
  - **`HomeA.dc.html` draws no gear** even though this doc has always said Settings opens from one in the Home header. The artboard's header row is the `Tankbook` wordmark plus the car chip. Treated as an artboard omission, not a contradiction: the gear goes in that row. The wordmark is optional chrome – the tab bar already names the tab, so the title/wordmark choice is free as long as the row stays single.
- **Entry card content (decided 2026-08-23, from reviewing the built screen).** Title is the station or vendor; the trailing figure is the amount in DIN. The subtitle line carries **quantity · odometer · date**, plus a **paperclip glyph when a receipt or photo is attached**.
  - **The same rule governs input, not just display.** A fill-up form must offer exactly the
    fuel kinds the selected car accepts, and when it accepts one, the row is a static value
    rather than a chooser - a control whose only options are "the answer" and "wrong" is not a
    choice. It must still be correctable (hard rule 13): reaching the car's fuel kinds has to be
    possible from the entry, or a mis-set car becomes an entry the user cannot fix. What is
    legitimately multi-valued: **petrol grades** (92/95/98/100, one tank, the driver picks at the
    pump), and **bi-fuel or flex-fuel** pairings (petrol + LPG, petrol + CNG, petrol + E85).
    What is not: **diesel together with petrol** - no car burns both, and offering it is how the
    Confirm sheet came to show a `95 / Diesel` toggle. Note `fuelGrade` is a separate field and
    stays free even for a single-kind car: a diesel driver really does choose between
    `ДТ-Е-К5 Танеко` and `АТ-Л-К5 Ультра`.
  - **Chip rows pack at the trailing edge and never compress a label (RV.28).** A row of
    multi-value chips (the fuel-kind chooser) is a wrapping flow: each chip takes the width its
    label measures at, chips pack against the row's trailing edge so they line up with the
    Full-tank toggle and the card's other right-hand values, and a chip wraps to the next row
    only when it genuinely does not fit. A flow must never use an `.adaptive` grid to lay chips
    out - adaptive DISTRIBUTES, stretching each column to fill the row so gaps grow and chips
    wrap early, and a grid that instead caps columns tight enough to stop the gaps compresses
    the widest labels ("100", "LPG") until they break inside their capsule. Both defects were
    shipped and caught by screenshot before the rule landed: the first is RV.28, the second is
    the `minimum: 44` regression the chooser's own comment records. The same contract governs
    any future chip row (currency, tire sets, reminders), not just fuel kinds.
  - **AdBlue rows** (2026-08-30): the kind label is always shown (it always differs from the car's usual), the leading glyph is a droplet, the accent stays `taillight` - it is a pump purchase; colour is never the only channel (the glyph is). In Trends, an AdBlue tile (`L / 1000 km`, `SCHEMA.md` → AdBlue) appears only when the car has two or more AdBlue fills, and never as a fifth tile competing with the four - it sits under them, small.
  - **Fuel kind is shown only when it tells the user something**: when the vehicle accepts more than one fuel kind, or when this entry's kind differs from the car's usual. A diesel-only car printing "Diesel" on every row is noise dressed as information – it costs a column and never varies. The rule is *conditional*, not "never": a petrol + LPG car, or a PHEV alternating fuel and electricity, genuinely needs it.
  - **The odometer takes that place**, because it is the one field that changes every entry, that the user is most likely to want to check against the dashboard, and that makes a mis-typed reading obvious in the stream instead of only in Trends. An entry with no odometer (optional on non-FillUp entries) simply omits the segment – no dash, no zero.
  - **Attachment presence is a glyph, never a word.** It answers "did I keep the receipt?" at a glance, which is a real question users ask at tax time, and it carries an accessibility label (colour and iconography are never the only channel).
  - Colour is never the only channel (accessibility floor below): fuel vs electric still differ by leading glyph as well as accent.
  - **Monthly dividers** carry the month's total spend in DIN, grouped by calendar month of the entry's date (not the log date), newest first. The total sums every entry type in the month; a **purchase group** (entries sharing a `purchaseGroupId`) is one receipt and counts once.
  - **Dated entry rows say WHICH year (decided 2026-09-06, RV.89).** A log spanning years must distinguish them: a row dated inside the CURRENT calendar year renders "18 Jul"; any other year appends the locale's own two-digit year ("18 Jul 15", en_GB "17 Aug 15", ru_RU "17 авг. 15 г."). The two digits come from `Date.FormatStyle.year(.twoDigits)`, so each locale uses its own convention, never a hand-composed apostrophe or a four-digit year on a row (the day is already printed, so "17 Aug 15" cannot be misread). The rule is relative to today at render time. ONE formatter (`EntryDateText` in core) sits behind every surface that lists dated entries: the Log rows, the flagged "needs a look" list, Recently deleted, Trends' last-price caption, the parts shelf, and the "Updated/Added" captions. **Month dividers** carry the month name alone inside the current year ("JUNE") and the FULL year outside it ("JUNE 2015"): a divider is a header with no day to anchor the date, so a two-digit year would read as a day ("AUGUST 15" looks like the fifteenth). Rows keep the compact two digits; headers carry the full year. The divider's DIN total is a number, not a date, and needs no year.
  - **Purchase groups** (P1.5): entries born from one receipt render as one grouped card, collapsible to a single row. The group's trailing figure is the **receipt total** (the sum of its logged lines); the fuel row inside shows the **fuel amount** – never the other way around (`docs/SCHEMA.md` CHECK 3).
  - **A log that ends where the data does not says so (RV.103).** The stream opens with the newest whole months covering ~20 rows; when a car's history is longer, the list's LAST element is a "Show N older entries" row – the caption action row (chevron.down + `Theme.Palette.action` text, hard rule 5) – and each tap adds the next whole months until the list is complete and the row retires. The pages are whole months, so a month divider never sits above a partial month (it always sums exactly the rows shown), and a divider's total never changes as more of the log is revealed.
- **Capture is polymorphic:** the center button opens the camera in auto mode (receipt / pump display detected automatically; a fiscal QR on a receipt is read as part of that receipt and is never named in the UI – `VISION.md`, 2026-08-30) with a mode row for Charge, Service invoice, and Expense – plus a "type manually" escape. One front door for every entry type.
- **Trends (chosen: tile grid)** is four sparkline stat tiles (consumption, cost/km, monthly spend, price/L), the household EV-vs-petrol comparison card, and insight cards below. Charts follow the same palette; no chart junk, thin `inkSoft` grid, `taillight`/`headlight` series only.
  - **A rate-pending month is a GAP in the spend and cost/km charts (RV.112, decided 2026-09-08).** A month whose rows are still waiting on a rate has no exact total, so the monthly series plot a point ONLY for a `.complete` month - a `.partial` month is not drawn at its known-so-far sum and a `.pending` month is not drawn at zero, because both read as "spend fell", which is a chart that lies (hard rule 2). A month whose known figures span home currencies (`.mixed`, RV.145) is a hole for the same reason - no single value exists to plot. Each unstateable month occupies a slot that renders as a HOLE: the line chart breaks its path there (it never bridges the gap with a straight line) and the bar chart leaves the slot empty without shifting its neighbours. A gap reads as "unknown", which is the truth; the F9 footnote carries the pending phrase. A tile whose current-month figure is `.pending` prints no number at all - it is omitted like any other data-hungry vital, never a `0 €`.
  - **The F9a timeline-neighbourhood chart (RV.117b, [v1.1], decided 2026-09-09).** The card under Edit entry's odometer conflict plots the entry's odometer-bearing neighbours with the offending point off the trend through the valid ones (the Drivvo presentation, `docs/COMPETITORS.md`). Rules, all shared with the sparkline: **no chart junk** (a thin `inkSoft` baseline and two quiet third-rules only), **x is the entries' real dates** (proportional spacing - never invented equal slots), y their readings, **amber is attention** - the offending point is `warn`, the neighbours quiet `inkSoft` context (this is not a taillight/headlight series, so the series-colour rule does not apply here). **Colour is never the only channel** (accessibility floor): the offending point is a larger `warn` diamond with an ink stroke while neighbours are small ink circles, and every point is its own accessibility element ("This entry" vs "Neighbouring entry", each with its reading and day as the value). The card's figures are **DIN with tabular alignment** (hard rule 6); the interval sentences beneath are SF copy - numbers inside a full localised sentence are copy, the same precedent as the F9a quote. The whole card renders only while the entry flags and has a `validRange`; a clean entry or one without an odometer shows no panel and no empty box.
- **Settings** opens from the gear in the tab-root header on each of the three tab roots (Log, Trends, Garage – never a fifth tab; the tab bar stays task-focused): account/sync status, appearance, language, notifications, data (import / export-always-free / recently deleted), Pro, and About & feedback. Per-car settings (currency, units, tank size) live on each car in the Garage, not here.
- Screen sources live in `design/screens/` (.dc.html per screen); web mockups use Archivo (condensed, variable width) as the DIN stand-in – the shipped app uses the real DIN faces bundled with iOS.
- Cards use 12pt corner radius, 1px hairline border (`ink` at 8%), flat – no shadows in dark theme, faint shadow in light.
- Spacing grid: 4pt base; screen margins 20pt; card padding 16pt.
- **An actionable card whose height follows the locale's text must never live in a `safeAreaInset`** (the one region that does not scroll): its height is subtracted from the scroll's budget, so RU's 20-30% longer text makes the card clip content at the fold that EN fits by luck. The import source picker's parse-error card owned that inset once and RU overflowed by 13-30pt, cutting the last scroll child's action line (RV.80, RV.84). Let the scroll own the overflow: the error card leads the scroll content, and while it shows, the actionable dead-end card is ordered directly under the list, above the coming-soon teaser. Nothing is dropped to make RU fit - the layout is what yields (hard rule 10: a phrase that fits only in English is a layout defect).
- **A row that navigates carries the chevron (RV.83).** The app has exactly ONE affordance for "this row leads somewhere" - the trailing `chevron.right` in `inkSoft` (inert decoration, never `action`, per the colour rules above) - and every full-width tappable row that is a door must show it. A full-width tap target that does not look tappable is an invisible feature for some users and an accidental tap for others (hard rule 7: an affordance that does not look like one is a next step the user cannot find). RV.79 shipped exactly that defect on the Garage per-car "N needs attention" strip - a full-width `NavigationLink` with no chevron on the same card whose own car row, 30pt above, carried one - and RV.83 gave the strip the chevron so the code and the artboard (`GarageReminderCounts.dc.html`) agree that the strip is the count's doorway, never a create action. The chevron is chrome, never content: it stays OUT of the row's VoiceOver label, which keeps naming what the row says (the car and the count) and never how it navigates.
- **An amber footnote that leads somewhere carries the chevron (PJ.57).** A footnote-size link is the same defect as the full-width strip, one row shorter: the excluded-count caption ("2 entries excluded") IS the route to the excluded entries, and until it carried the chevron it was byte-identical to a caption that does nothing - colour cannot mark the difference, because amber is attention, never action (hard rule 5), and recolouring a link that sits on an amber warning would break the very rule the caption obeys. So the affordance is structural: the link branch renders the count phrase plus the trailing `chevron.right` in `inkSoft` (the RV.83 vocabulary, unchanged tone - `inkSoft` beside amber text is already the Garage strip's pairing), while a genuinely passive caption stays text alone. The two must never be made "consistent" by giving both the chevron: identical pixels for different behaviour is the defect. The count phrase stays the button's whole VoiceOver label; the chevron is chrome and never enters it. The `[RV.159]` consents are the same comprehension class - "drawn as the same object" - on a different surface, and are cited rather than repeated here.

## Iconography & app icon

- SF Symbols throughout, `regular` weight, monochrome `inkSoft` (accent color only when the icon *is* the state, e.g. anomaly badge).
- App icon (**settled 2026-08-30, product owner: "the pump icon was absolutely fine"**): the **fuel pump** – body with its window, base line, hose to a spout, and a checkmark – in `taillight` strokes on `midnight`. It is the mark Welcome and the site header carried since P1, now also the icon; `design/brand/icon.svg` is the single vector source (the icon set, Welcome's `BrandMark` and the site favicons render from it; `design/brand/README.md` has the steps). The check is a "done" mark in the same colour – `headlight` stays electric-only (hard rule 5). Legible at 29pt, no text. **Alternative kept for the record:** the generated gas-pistol-and-charging-plug icon under `design/brand/alt-pistol-plug/` and on the canvas's Brand page, with the other directions tried that day. **Shipped 2026-08-30** as an iOS 18 single-size set in `ios/App/Resources/Assets.xcassets/AppIcon.appiconset`: **Any/light** = `taillight.light` on `midnight.light`, **Dark** = `taillight` on `midnight`, **Tinted** = white glyph on transparent for the system tint. Full-bleed square – iOS applies the mask; never pre-round the corners.

## Voice

- Plain verbs, sentence case: "Save fill-up" → toast "Saved". Same word through the whole flow.
- The app talks in the user's metrics, immediately: after saving, the confirmation is not "Entry saved" but "6.8 L/100km – your best this year."
- Errors say what happened and what to do: "Couldn't read the price. Tap to type it." Never apologetic, never vague.
- Numbers respect the user's locale (comma decimals where applicable) and the entry's original currency, with home currency in `inkSoft` beneath.
- **Entry forms follow one field order: Date · Odometer · Station · Fuel · the numbers · Currency.** It holds for the Confirm sheet and Edit entry alike, so muscle memory transfers between the screen you scan into and the screen you correct in. Two consequences are deliberate. **The odometer sits second**, directly under the date: it is the field consumption depends on, the one a scan can never read, and it spent P1 and P2 below the fold behind a pinned Save bar because the artboards lead with the three-number card - which is the order the *scan's payload* arrives in, not the order a person fills a form in. **Currency comes last and is folded** while the entry is in the home currency: paying abroad is rare, the chip row cost ~100 pt of the first screen, and it opens itself whenever the currency is uncertain or genuinely foreign (P2.5 - never silently convert). `ConfirmA.dc.html` and `EditEntry.dc.html` still draw the older sequence; this rule supersedes them, and they are redrawn when either screen is next reworked.
- **Money renders amount-then-symbol, always, separated by a no-break space**: `390 €`, `68.46 €`, `1.679 €` - never `€390`. One screen must not carry two conventions, and until 2026-08-25 Home did exactly that (the spend tile and month divider printed `€390` directly above rows printing `68.46 €`). The artboards draw amount-then-symbol five times against a single `€212`, and the examples in this document have always done the same, so the symbol-first form was the outlier. The separator is **U+00A0**, not the `&thinsp;` the artboards write: DIN Alternate has no glyph for U+2009 and drops it silently (see `OdometerFormat`), and a plain space would let a figure break across lines.
- **Every money figure renders its currency's SYMBOL, converted or not (RV.145, decided 2026-09-08 - do not relitigate)**: `2416.00 $`, never `2416.00 USD`, and never a bare `2416.00 `. The symbol always belongs to the FIGURE it sits beside - a euro sum carries `€` even on a dollar car - because a figure and its marker read from two different objects is how the Log once printed `91 $` above `36.06 €` rows. A rate-pending row shows its ORIGINAL amount with the ORIGINAL currency's symbol, dimmed: the unconverted state is told apart by the dimming, the row's own identifier, and the divider's pending phrase, not by downgrading the marker to a code (this reverses the code-not-symbol rule that predates RV.145; the two-currencies-on-one-screen state that rule existed to guard is itself gone). **A currency whose symbol is not distinct from its code falls back to the code** - CHF renders `2416.00 CHF`, never an empty marker. The fallback is ONE named path (`AddVehicleSupport.moneySymbol`), not a per-call-site accident; the raw `currencySymbol` helper stays empty for the chip labels that show the code alone (`currencyLabel`).
- **A month's spend total carries the currency it is denominated in (RV.145)**. The divider, the vitals tile, the guest strip, `VehicleVitals` and the Trends spend tile all render a month's figure through the one `HomeFormat.spend(MonthTotal)`, so the symbol always comes from the same object as the figure. A month whose known rows span home currencies (a home-currency change leaves older snapshots in their old home; docs/SCHEMA.md -> Money) is **`.mixed` and displays per-currency subtotals** - `91 € · 45 $`, each figure exact under its own symbol - never a single number that is not a quantity of anything, and never a conversion between home currencies (hard rule 3). On the compact surfaces (vitals tiles, guest strip) the breakdown is one string, scaled like any long figure; on the Trends chart a mixed month is a hole, exactly like a rate-pending one, because no single value exists to plot.
- **The price-per-unit vitals are home-denominated, like every money figure (RV.29, decided 2026-09-03).** The "Last price/L" vital on Home and the "Price / L" tile in Trends show the *converted home* price, never the raw original under a home symbol - a fill's `unitPrice` is stored in the currency it was paid in (`SCHEMA.md`, FillUp), and a RUB-home car stamping `₽` on a EUR `1.919` is the money pair at its most direct lie (hard rule 3). The conversion uses the entry's OWN immutable rate snapshot, so the figure never shifts as rates move; the symbol printed is the figure's own currency. A fill whose rate is still pending has no home figure - it is skipped exactly as `monthSpend` skips one (F9), so the tile shows the most recent price expressible in home currency, and is omitted (never "N/A") when none exists. Home and Trends share one derivation, so a sparkline never plots a foreign litre against home litres and its final point is always the tile's figure.

## Accessibility floor

Non-negotiable: full Dynamic Type support (DIN metrics scale with it), WCAG AA contrast in both themes (each accent uses its darker light-theme value on white; large DIN numerals qualify for the 3:1 large-text threshold, body-size accent text does not sit on accent grounds), VoiceOver labels that read metric + unit + trend ("consumption 6.8 liters per 100 kilometers, improving"), Reduce Motion and Increase Contrast respected, tap targets ≥ 44pt. Color is never the only channel: fuel vs electric entries also differ by glyph, and warnings also carry an icon. Accent contrast is not eyeballed: `PaletteAccentGuardTests` computes the WCAG ratios for every accent on `midnight` and `dash` in both themes and fails under 4.5:1 (W8 - light `headlight` at `#0E7FA6` measured 4.22:1 on light `midnight`, so the token moved to `#0A6A8C`, 5.62:1 and 6.08:1).

**The VoiceOver label is composed, never a bare figure (P6.5).** A stat figure announces its *value + unit + trend* as one element - "6.8 L/100, improving" - and the subordinate unit is hidden from VoiceOver on its own, so it is never read twice. The hero headline reads its unit *spoken*, not as the compact glyph ("liters per 100 kilometers", never "L/100km" - which a screen reader voices as "L one hundred k m"); `L10n.spokenHeadlineUnit` is the spoken form, `L10n.trend` the direction word. **The trend is derived, never stored (hard rule 2):** `TrendDirection.lowerIsBetter(_:)` reports "improving"/"worsening" from the last two points of a lower-is-better series and abstains - `nil` - with fewer than two points, a flat series, or a change under 1%, so VoiceOver never announces a direction the data did not earn. Wired into `HomeStats.headlineTrend` and `TrendsStats.consumptionTrend`/`costTrend`, guarded by `AccessibilityGuardTests`.

**Increase Contrast is honoured on the card hairline (P6.5).** The palette is already AA, so text does not change; what changes is the decorative `Theme.Palette.hairline` border (ink at 0.08 - near-invisible on some displays). `ContrastPolicy.hairlineOpacity(increasedContrast:)` raises it to 0.24 when the user has Increase Contrast on; `CardSurface` (the one `formCard()` every card renders through) reads `\.colorSchemeContrast` and applies it.

**The entry kind is a glyph, never colour alone (P6.5).** The log row's kind marker is `EntryKindMark`: `fuelpump.fill` in `taillight`, `bolt.fill` in `headlight`, `wrench.adjustable.fill`/`tag.fill` in `inkSoft` for service/expense - so fuel vs electric differ by icon, not just hue, and the marker's accessibility label names the kind for a blind reader. One component, shared by Home and Recently deleted, guarded by `AccessibilityGuardTests`.

**Tap targets ≥ 44pt - the toolbar glyph buttons are the shipped fix (P6.5).** The Reminders row's Complete/actions glyphs and the form's clear-date/clear-odometer glyphs now carry a 44pt frame. **Recorded, not fixed:** the Add/Vehicle-detail fuel-kind chips and powertrain segment control render ~31-35pt tall - under 44. Raising them to 44 grows the Add car form ~22pt, which surfaces a pre-existing keyboard-avoidance defect (the form's scroll viewport squeezes to ~44pt under the keyboard and the odometer field lands beneath it), breaking `AddVehicleUITests`' odometer scroll. The chip fix must ship together with that keyboard-layout fix.

**Text on an accent fill is its own rule (P6.19).** The floor above measures accents as *foreground on a ground*; it says nothing about the reverse - *text drawn on an accent fill* - and white on an accent fill fails in the dark theme, the brand's home: `Color.white` on `warn` is **2.15:1** (below even the 3:1 large-text floor) and on `taillight` **3.47:1** (every primary button), both in dark; the same white passes in light (5.23:1 and 5.07:1), which is exactly how this shipped - the pair looked fine in the light screenshots. The only text token that clears 4.5:1 on every accent fill in both themes is `midnight` (dark 8.66:1 on `warn`, 5.37:1 on `taillight`; light 4.84:1 and 4.69:1), and it adapts - near-black in dark, near-white in light. So: **text on an accent fill is always `Theme.Palette.midnight`, never `Color.white`**, nor `ink`/`inkSoft` (both sit under 4.5:1 on every accent fill). A tinted selection wash (`accent.opacity(...)`, e.g. the segment chips at `taillight.opacity(0.14)`) is not a fill - it is a blend with the ground, and `ink` on it clears AA (12.05:1 dark) - but the moment a wash is raised to a solid fill, the midnight rule applies. Enforced by `PaletteAccentGuardTests.textOnAccentClearsAA` (computes every text-on-accent pair the sources draw and fails under 4.5:1 - the mutation is restoring `Color.white` on `warn` and watching it fail at 2.15:1) and by the `noWhiteForegroundOnAccentFill` source guard, which scans `ios/App/Sources` for `Color.white`/`.white` over an accent fill.
