# RV.272 + RV.273 - stored litres crossing into the car's unit without conversion

**Scenarios: J3 · the 5-second fill-up (RV.272, `[!]`), J3b · type it (RV.273).** The last two
places `RV.234`/`RV.271` found where a litre value meets a per-unit label; RV.272 is
data-corrupting and is the reason J3's status line is cleared.

## RV.272 - the scan pre-fill on an imperial car

`ManualFillUpView.swift:398` writes `extraction.liters` (litres by contract - `SCHEMA.md` ->
`GatewayExtraction.volume`) straight into `form.liters`, and `:499` does the same for the
gateway's `.volume`. The numbers card treats `form.liters` as the car's DISPLAY unit
(`ManualFillUpMath.derived(volumeUnit:)`), so on a gallons car a scanned 40 L receipt reads
*40.00* under **Gallons** and saves as ~151 L. Silent, confident, wrong - the F2 shape.

**Build**: convert at the pre-fill boundary with the ONE converter
(`ManualFillUpMath.displayVolume(from:unit:)`, `Validation/ManualFillUpMath.swift:90`) at both
sites, through one function both call; do the same for `pricePerL` (per litre → per display unit,
the inverse factor). `resolvedByExtraction` semantics unchanged. Check the QR/fiscal path
(`ExtractionAssembler`, the RU/KZ anchor) lands in the same function - it is a third writer if it
does not.

**Tests**: L1, FAILS TODAY - a 40 L extraction pre-fills *10.57* on a US-gallon car, *8.80* on a
UK-gallon car, and the save stores 40 L; the price/litre pre-fills as price/gallon; metric
unchanged. L4 `CaptureUITests` on an imperial car with a seeded receipt (`-seedImperial…` -
read `CaptureUITests+RV134.swift` for the existing imperial seed): the volume row reads the
converted figure. EN + RU screenshots `RV.272-confirm-imperial-scan`.
**Mutation**: write litres again; the L1 goes red on *40.00 != 10.57*. Verbatim.

## RV.273 - two more stored-litre values under a per-unit label

- `AttachmentRecognisedView.swift:224-225`: the recognised page's `.volume` prints under
  `L10n.volumeUnit(.l)` while its label is per-unit since RV.234.
- `RecentlyDeletedView.swift:247`: `fill.volumeL` prints under the car's unit with no conversion.

Route both through the same `displayVolume`. L1 per site, metric and imperial; mutation: drop
the conversion, red. Screenshots only if a committed frame changes (check the manifest).

## Gates

`swift test` in full, lint 0, `CaptureUITests` and `RecentlyDeletedUITests` in their own
invocations with counts, the app-target bundle, Release if a DEBUG seed is touched. Then grep the
tree for `volumeL` and `.liters` reaching a `Text` without `displayVolume` - the list is the
deliverable; it should be empty.
