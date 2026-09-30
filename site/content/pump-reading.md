+++
title = "How Tankbook reads a pump display"
description = "Follow a pump photo from tilted digit rows to editable fill-up figures, including the arithmetic check, warning states and measured reader changes."
+++

In Tankbook 1.1, a photo of the pump display can give you a head start on a fill-up. The app suggests the total, volume and price it can read. You check the figures beside the photo before saving. Typing them from the start is an equal way in.

The difficult part is choosing which digits deserve a place in the form. A misplaced decimal point can turn a plausible fill-up into a very different one.

## The rule behind the reader

A wrong digit costs more than an empty field. The reader therefore checks the shape of a digit row, its place on the display and the arithmetic linking the figures. It can leave a field empty. If it can read digits but cannot close the arithmetic, it may offer those digits with a warning instead of presenting them as checked. Every suggested figure remains editable.

## From photo to figures

The capture pipeline first turns the camera image upright. It finds digit rows, decides whether the photo shows a pump display, straightens the rows, assigns their roles, reads their digits and checks the resulting figures. Ordinary text recognition also runs on the photo and can supply a field the pump reader leaves open.

{{< diagram name="pipeline" caption="The display reader finds and reads rows; the arithmetic check decides which values are supported before the review screen opens." >}}

### Find the rows

Input: the upright photo. Output: candidate quadrilaterals around digit rows.

RowSeg works in the PixelLink manner. It marks pixels likely to belong to a row and links neighbouring marked pixels. Connected groups become row shapes. A fitted, rotated quadrilateral follows the row's own angle, including a display photographed obliquely. A row may belong to the transaction, a price board for different fuels, or something irrelevant on the pump face.

### Decide whether this is a display

Input: the candidate rows. Output: a display decision or the ordinary document route.

The quick decision looks for large digit rows stacked in the same part of the image. If that evidence is short, the reader checks proposed rows by their shape and counts text lines in the photo. A receipt has many printed lines; a pump face can have labels too, so the text count belongs only to this slower decision. A photo routed to the display reader still has to pass the later reading check.

{{< diagram name="decision" caption="Stacked rows can identify a display early; uncertain photos get a closer check of row geometry and surrounding text." >}}

### Straighten and inspect each row

Input: a candidate quadrilateral. Output: a straight strip and a geometry verdict.

The reader maps the quadrilateral onto a flat strip, sampling the photo so tilt and perspective are corrected together. A slicer examines the strip's bright or dark digit strokes, the repeating spacing of character positions, gaps and the decimal mark. It can reject a keypad or a printed label whose geometry does not resemble a display row. A row just beyond one shape limit can still be offered to the later check at a lower rank.

The slicer no longer supplies the transaction's digits. Its cells still help verify candidate rows and, when needed, tell which way a sideways display is upright.

{{< diagram name="warp" caption="The four corners of a tilted row are mapped onto a straight strip before its shape and digits are read." >}}

### Give the rows their roles

Input: the accepted row shapes. Output: total, volume, transaction price and price-board roles.

The reader first accounts for the display's common tilt. It groups nearby, similarly sized grade-price windows into a board and sets those aside. It then orders the transaction column by position: total above volume, with the transaction price below when it is present. Some pump heads put the price among grade prices. The arithmetic check may reject a value, but it does not swap row roles to manufacture a matching calculation.

{{< diagram name="roles" caption="Position separates the transaction column from nearby prices for other fuel grades." >}}

### Read a whole row

Input: the straightened colour strip. Output: a digit sequence, a possible decimal mark and ranked alternatives for uncertain digits.

RowRead is a CRNN trained with CTC. It reads across the strip as one sequence. CTC combines different paths through the network's outputs that spell the same string, including paths with blank positions between repeated digits. The decoder keeps likely strings, then checks alternative digits and decimal positions. Those alternatives matter when glare makes one segment of a digit hard to see.

{{< diagram name="ctc" caption="Several network paths can spell the same row; their evidence is combined before the arithmetic check uses the digits." >}}

### Check what the figures can mean

Input: ranked readings for volume, price and total. Output: values supported by the check, or a caution with the best available readings.

The law of reading tries plausible digit and decimal placements. It checks whether volume multiplied by unit price gives the displayed total after the pump's cent rounding or truncation. A round preset amount has its own narrow allowance because the displayed volume is rounded. A single uncertain segment may be repaired when the network also gives the replacement some support. Competing readings that imply different values can leave a field unresolved.

Currency helps place the decimal mark and judge a plausible price. The car's home currency is tried first, with the region used when no car currency is available. If that convention closes nothing, the reader tries its other measured conventions and takes the values supported by the most closing conventions. A currency printed on the display is useful context for a person checking the photo; the current reader does not yet feed that print into its currency choice. A mismatch with the car's currency alone cannot hide a closing read.

When the transaction price is absent, the reader may use a price shown elsewhere on the display to check total and volume. If the shown price differs from the implied price, it can offer the pair with a warning and leave price for you to enter. If no convention closes, sufficiently clear top readings may still be offered as unchecked figures. An idle display with zero volume does not become a fill-up.

{{< diagram name="law" caption="Candidate digits and decimal placements must agree with the displayed arithmetic; an unchecked best read carries a warning." >}}

### Try another orientation, then let you check

Input: a display whose first reading commits no field. Output: a better supported reading if a quarter turn helps.

The reader compares sideways orientations by how many plausible rows survive the geometry check. If opposite orientations look alike, the older segment classifier's digit confidence breaks the tie. It then runs the full read in the chosen orientation. A read whose arithmetic did not close still gets this chance before its warned figures reach the form.

On the review screen you see the photo and editable figures together. When all the offered figures fail the arithmetic check, the amber notice says, “These numbers don't multiply up – check them against the photo.” If a figure is missing, it says it could not check the numbers and asks you to type the missing one from the photo. A photo with no readable figures opens with a request to type them; the photo stays attached. Nothing is saved until you save the fill-up.

## Where a display can fool it

A night photo taken at an angle may still yield good row shapes once they are straightened. A nearby board of grade prices is harder: one of its prices can resemble the transaction price, so position and arithmetic both matter.

{{< photo name="night-tilt" caption="A tilted night display with transaction rows and a separate price board. The row angles help the reader straighten the figures." >}}

Screens with printed fonts, adverts or strong reflections can produce convincing false rows or hide real ones. A dark LCD may leave too few rows to identify the transaction. In those cases the review screen can be sparse or empty. The photo remains there while you type the figures.

{{< photo name="tokheim-tft" caption="A screen display mixes transaction figures with other text. Row finding alone cannot establish which figures belong to the fill-up." >}}

## Two generations of the reader

The first generation, shipped on 20 September 2026, used a Create ML object detector to find digit rows. Its model occupied about 31 MB and returned upright rectangles. A slicer cut each rectangle into character cells. A roughly 64 KB classifier produced eight outputs for each cell: its seven segments and decimal point. It matched the lit segments to the nearest of ten allowed digit patterns. The arithmetic law sat above that reading.

That arrangement was sensitive to the crop. In a comparison using the same hand-drawn rows, upright rectangles led to 89 read cells; rotated quadrilaterals led to 111. The original detector had learned mostly level displays: 90% of its training boxes were tilted less than 4°. Loose or clipped rectangles damaged digits, while slicing lost many more cells. Night displays, amber LEDs and screen displays were thinly represented or absent.

The second generation arrived in two steps on 25 September 2026. RowSeg replaced the upright detector with a PixelLink-style pixel-and-link segmenter. Its 1.8 MB model fits rotated quadrilaterals to row pixels. RowRead then replaced character-by-character transaction reading with a 3.9 MB CRNN trained using CTC. The old slicer and cell classifier remain for geometry checks and orientation.

On 68 held-out pump photos that trained neither model, the old locator committed 47 cells, all correct. Replacing only the locator gave 62 committed cells, 61 correct. Adding the whole-row reader gave 117, of which 116 were correct. Photos with every assessed field right rose from 21 to 40 out of 68. On the same held-out row comparison, median overlap with hand-drawn rotated rows rose from 0.771 to 0.861; false rows per photo fell from 0.647 to 0.088. These are results for that snapshot of models and photos, not expected performance on every pump.

## How we measure

The models learn from a labelled training split. The held-out photos stay outside training, and the scorer compares the values offered by the app path with the figures marked on those photos. It counts committed fields, correct committed fields and coverage separately. A field shown with a caution is reported separately from a checked commitment, because the screen asks the user to treat them differently.

The bundled 1.1 gate records a later reader measurement on 68 held-out photos with 183 assessable numeric fields: 128 fields committed, 127 correct. That measurement passes the build's precision and coverage gates, but it does not guarantee an individual reading. The checked photo beside the editable form is still the final judge.
