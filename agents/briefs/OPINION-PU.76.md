# OPINION-PU.76 - an independent second opinion on the oriented row detector's method

**Read-only.** Write exactly one file: `agents/reviews/PU.76-OPINION-astra.md`. No code, no commits,
no builds that write.

A research agent (Qwen 3.8 max) is writing `agents/research/PU.76.md` in parallel - do NOT read it;
this opinion must be independent so the two can be compared.

**The question.** The pump reader's row detector (`ios/Sources/TankbookCore/Extraction/PumpReader/
PumpRowDetector.swift`, a Create ML object detector, ~31 MB, upright boxes only) frames turned display
rows badly: the owner's hand boxes read as upright rectangles commit 89 cells at 0.944 precision, the
same hand boxes as turned quads 111 at 0.991 (`docs/EXTRACTION.md`, the PU.64 apportionment paragraph);
three retrains on rotated data were refused (`docs/TASKS.md` PU.66); a turned row comes out as a small
upright box (PU.70's cut row). The target is an on-device (iOS 18, iPhone 12 floor, Core ML) detector
that outputs a turned quad per digit row, or an equivalent. `docs/TASKS.md` PU.76 names candidate
families: TextBoxes++, rotation proposals (Ma et al. 2018), PixelLink, Oriented R-CNN; also consider
small one-stage detectors with oriented-box heads, segmentation then minimum-area rectangle, and the
cheap baseline of keeping the upright detector and turning each row by the fast Hough angle the code
already computes (`PumpRowDeskew.angle(of:)`, PU.69).

**Answer:** rank at most four options for THIS problem - small corpus (a few hundred stills, hand
quads), on-device Core ML, a bundle-size budget - each with its expected payoff, its main risk
(training data, Core ML conversion, latency), and the cheapest experiment that would falsify it. Say
which to spike first. Cite any paper with title, authors, year and link, and say whether you verified
it exists; a misattributed citation is worse than none.
