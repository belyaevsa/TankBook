# B3 measured: cropping the display and re-reading it is NOT worth building

Run 2026-09-05 by the orchestrator, directly, because two analysts who had opened the
photographs disagreed about it and an argument between them could not settle a question about
what Vision does.

## The question

When the full-frame pass returns a digit run with **no decimal separator** - `12522` for
`125.22`, `8792` for `87.92` - does re-recognising that observation's own bounding box, cropped
and optionally upscaled, recover the separator? `RESEARCH-pump-vision.md` said no ("making it
bigger does not make it a character"); `RESEARCH-pump-qwen.md` said yes ("a resolution/attention
failure on small glyphs, which is exactly what crop-and-upscale fixes"). Both cited `pump-005`.

## The method

For every one of the 66 pump fixtures: run Vision on the full frame; take each returned digit
run of 4+ characters with no `.` or `,`; crop that run's own box with 25% padding; re-run Vision
on the crop at 1x and at 2x with high-quality interpolation; and compare what comes back against
`expected.csv`. Script: `scratchpad/cropexp2.swift` (not committed - it is a probe, and the
numbers below are the artefact).

**A separator in the wrong place is the outcome that matters**, so "did a separator appear" and
"was the value right" are counted separately.

## The result

    separator-less digit runs examined:            148
    crop only, produced ANY separator:              19
    crop only, produced the GROUND-TRUTH value:      7
    crop + 2x upscale, ANY separator:               15
    crop + 2x upscale, GROUND-TRUTH value:           5
    cases where upscaling LOST what cropping got:    4
    fixtures with at least one recovered value:       5   (of 66)

Three findings, in order of how much they change the plan.

### 1. Upscaling makes it worse, not better

Crop alone recovers 7 correct values; crop plus a 2x upscale recovers 5, and in 4 cases the
upscale destroys what the plain crop got right. `pump-057` is the clean example: the crop reads
`100,38` - the truth - and the 2x upscale reads `10036`, which is both separator-less **and a
wrong digit**. Interpolating a seven-segment glyph invents edges that were not photographed.

**So the vision analyst was right about upscaling** and the mechanism it named ("the dot is not a
character Vision emits; making it bigger does not make it one") is confirmed. Nothing in this
experiment supports any upscaling step.

### 2. Isolation - not resolution - is what occasionally recovers a separator

Where a separator does come back, it comes back at **1x**: the crop changes nothing about the
pixels, only about what surrounds them. Removing the forecourt makes Vision treat the window as
its own line rather than as part of a busy scene. `pump-005`'s `8792` becomes `87.92`,
`pump-057`'s `10038` becomes `100,38`, `pump-059` yields `102,98`, `0054,23` and `1,899`.

**So qwen was right that the information is in the pixels** - but wrong about the mechanism, and
the mechanism is what a design would have been built on.

### 3. And this is why it must not ship as written: the recoveries are mostly WRONG

Of the 19 runs where a crop produced a separator, only **7** matched a ground-truth value. Two
more are legitimate readings of values `expected.csv` does not carry (a board price on
`pump-009`). **The remaining ten are wrong, and several are wrong by a factor of ten:**

| fixture | full frame | crop returned | truth |
|---|---|---|---|
| pump-037 | `1105` | `1.05` | **11.05** |
| pump-057 | `005580` | `5,80` | **55.80** |
| pump-049 | `74798` | `40,98` | **10.98** |
| pump-003 | `8525` | `85,2` | **85.25** |
| pump-029 | `5700` | `5 7.00` / `51.00` | **57.00** |
| pump-025 | `4094` | `40.9` | **40.99** |

A factor-of-ten volume is the worst error this corpus can produce: it is invisible to the
arithmetic cross-check (scale-invariant), invisible on a Confirm sheet, and permanent in the
user's history. A stage that produces ten of those for every seven correct values is not an
accuracy improvement, it is a hazard generator.

## The verdict

**B3 is closed: do not build the crop-and-re-read stage as a recogniser.** It is worth about +7
cells across 66 fixtures at the cost of ~10 confident-wrong values, and the cheap half of it
(upscaling) is actively harmful.

The one thing worth keeping from it is narrow and conditional: **a crop at 1x is a candidate
GENERATOR, never a value source.** If B2's scale search is ever unable to pin a value from the
full-frame digits, a 1x crop of that field's own box may add a candidate to the search - and the
search, not the crop, decides. That inverts the trust: the arithmetic validates the reading
rather than the reading being believed. It is worth doing only after B2's ladder is finished,
because on this evidence the ladder resolves the same fixtures more safely from the digits it
already has.

## What this says about the method

The two analyses disagreed for a good reason: **both were looking at the same true fact from
different sides.** The separator IS in the photograph, and Vision DOES refuse to emit it, and
neither of those observations tells you what a pipeline should do. Only running it does. An
afternoon of measurement replaced an argument that could not have been won on either side's
evidence.
