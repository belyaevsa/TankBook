# Tankbook – Design Language

*Companion to `VISION.md`. Defines the visual and interaction style for the iOS app.*

## Direction: the night drive

The identity comes from the road at night: blue-black asphalt, taillight red-orange ahead, headlight cyan sweeping past. Dark is the brand's home theme (the app is mostly opened standing at a pump or a charger); light theme is its overcast-daylight counterpart. Chosen from a four-option palette exploration (Night Forecourt, Deep Petrol, Night Drive, Ledger) – Night Drive won for being the most unmistakably automotive.

One sentence to test every decision against: **the app should feel like a precision instrument, not a finance form.**

## Color

Semantic first: the two accents are not decoration, they encode powertrain. Everything that burns fuel is taillight red-orange; everything electric is headlight cyan. The EV-vs-petrol household comparison inherits its color coding from this rule for free.

| Token | Dark (home) | Light | Role |
|---|---|---|---|
| `midnight` | `#101318` | `#F5F6F8` | Background (blue-black asphalt / overcast daylight) |
| `dash` | `#1A1F27` | `#FFFFFF` | Cards, sheets |
| `ink` | `#EAEDF2` | `#1A2028` | Primary text |
| `inkSoft` | `#98A2B3` | `#55606E` | Secondary text, captions |
| `taillight` | `#F4503A` | `#D63A26` | Primary accent: fuel entries, hero numbers, main CTA |
| `headlight` | `#4FC3E8` | `#0E7FA6` | Electric: charging entries, kWh metrics |
| `warn` | `#F0A030` | `#B06E10` | Anomalies, failed cross-checks, overdue reminders |

Rules:
- One accent per screen region. A fuel card never shows cyan, a charge card never shows taillight.
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
- The **cross-check line** is validation made visible: while `liters × price ≈ total` is unresolved it renders as a thin `inkSoft` rule; when it locks, it fills `taillight` with a tick and a light haptic. If it can't lock, the mismatched field gets a `warn` amber underline and the tap-to-edit affordance – never a modal alert.
- Low-confidence OCR fields render at 60% opacity until confirmed by tap or edit. Confidence is shown, not hidden.

## Motion

Three orchestrated moments; nothing else animates beyond system defaults.

1. **Digit roll:** hero metrics change with an odometer-style vertical roll (per-digit, 250ms, spring). Used on the dashboard when a new entry lands.
2. **Cross-check lock:** the rule draws in from both ends toward the tick, paired with `.success` haptic.
3. **Capture handoff:** the receipt photo shrinks into the Pump Card, which flips up from it – camera and card feel like one object.

All three degrade to crossfades under Reduce Motion.

## Layout & navigation

- **Tab bar:** Log · **Capture** · Trends · Garage. Capture is a raised `taillight` circle, center, always one thumb-tap from anywhere – the app's front door.
- **Home (chosen: Garage-first)** leads with the car card – photo, name, odometer, three vitals – a reminder surface, and recent entries; the full reverse-chronological stream of all entry types (fuel, charge, service) lives behind "All entries", distinguished by accent color and leading glyph. Monthly dividers carry the month's total spend in DIN.
- **Capture is polymorphic:** the center button opens the camera in auto mode (receipt / pump display / fiscal QR detected automatically) with a mode row for Charge, Service invoice, and Expense – plus a "type manually" escape. One front door for every entry type.
- **Trends (chosen: tile grid)** is four sparkline stat tiles (consumption, cost/km, monthly spend, price/L), the household EV-vs-petrol comparison card, and insight cards below. Charts follow the same palette; no chart junk, thin `inkSoft` grid, `taillight`/`headlight` series only.
- **Settings** opens from a gear in the Home header (never a fifth tab – the tab bar stays task-focused): account/sync status, appearance, language, notifications, data (import / export-always-free / recently deleted), Pro, and About & feedback. Per-car settings (currency, units, tank size) live on each car in the Garage, not here.
- Screen sources live in `design/screens/` (.dc.html per screen); web mockups use Archivo (condensed, variable width) as the DIN stand-in – the shipped app uses the real DIN faces bundled with iOS.
- Cards use 12pt corner radius, 1px hairline border (`ink` at 8%), flat – no shadows in dark theme, faint shadow in light.
- Spacing grid: 4pt base; screen margins 20pt; card padding 16pt.

## Iconography & app icon

- SF Symbols throughout, `regular` weight, monochrome `inkSoft` (accent color only when the icon *is* the state, e.g. anomaly badge).
- App icon: `taillight` fuel-nozzle silhouette whose hose draws a subtle checkmark, on `midnight` – night-drive at a glance on the home screen, legible at 29pt. No text in the icon.

## Voice

- Plain verbs, sentence case: "Save fill-up" → toast "Saved". Same word through the whole flow.
- The app talks in the user's metrics, immediately: after saving, the confirmation is not "Entry saved" but "6.8 L/100km – your best this year."
- Errors say what happened and what to do: "Couldn't read the price. Tap to type it." Never apologetic, never vague.
- Numbers respect the user's locale (comma decimals where applicable) and the entry's original currency, with home currency in `inkSoft` beneath.

## Accessibility floor

Non-negotiable: full Dynamic Type support (DIN metrics scale with it), WCAG AA contrast in both themes (each accent uses its darker light-theme value on white; large DIN numerals qualify for the 3:1 large-text threshold, body-size accent text does not sit on accent grounds), VoiceOver labels that read metric + unit + trend ("consumption 6.8 liters per 100 kilometers, improving"), Reduce Motion and Increase Contrast respected, tap targets ≥ 44pt. Color is never the only channel: fuel vs electric entries also differ by glyph, and warnings also carry an icon.
