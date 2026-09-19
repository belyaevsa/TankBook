# Live Photo pump captures

Live Photos (HEIC key frame + the paired `.mov`) of pump displays, shared by the product owner on
2026-09-19 for PU.19 (per-cell fusion over frames). Every one is a fill that is ALREADY in
`../pump/`, so the still fixture's `windows.json` entry is the oracle and the still-only score is
the before:

| live | frames | key frame | same fill as | total / liters / unitPrice |
|---|---|---|---|---|
| `live-6227.mov` | 24 (4K video, no HEIC) | - | `pump-097` | 43.39 / 22.85 / 1.899 |
| `live-6228` | 32 | `live-6228.heic` | `pump-097` | 43.39 / 22.85 / 1.899 |
| `live-6229` | 53 | `live-6229.heic` | `pump-098` | 19.76 / 9.69 / 2.039 |
| `live-6230` | 48 | `live-6230.heic` | `pump-099` | 20.21 / 10.64 / 1.899 |
| `live-6231` | 57 | `live-6231.heic` | `pump-100` | 129.62 / 64.04 / 2.024 |
| `live-6237` | 50 | `live-6237.heic` | `pump-101` | 35.90 / 17.65 / 2.034 |
| `live-6238` | 35 | `live-6238.heic` | `pump-102` | 19.97 / 10.22 / 1.954 |
| `live-6239` | 33 | `live-6239.heic` | `pump-103` | 94.93 / 48.58 / 1.954 |
| `live-6240` | 68 | `live-6240.heic` | `pump-104` | 51.65 / 26.50 / (price washed out) |
| `live-6242` | 42 | `live-6242.heic` | `pump-105` | 48.52 / 25.55 / 1.899 |
| `live-6245` | 24 | `live-6245.heic` | **new fill** (Gilbarco, Circle K EE) | 87.35 / 45.40 / 1.924 |
| `live-6246` | 48 | `live-6246.heic` | **new fill** (Gilbarco, Circle K EE) | 50.02 / 25.60 / 1.954 |
| `live-6259` | 31 | `live-6259.heic` | `pump-111` | 100.87 / 50.46 / 1.999 |
| `live-6260` | 40 | `live-6260.heic` | `pump-112` | 10.14 / 4.61 / 2.199 |
| `live-6261` | 28 | `live-6261.heic` | `pump-113` | 10.51 / 5.22 / 2.014 |
| `live-6262` | 19 | `live-6262.heic` | `pump-114` | 144.91 / 69.87 / 2.074 |

The two new fills are not in `../pump/expected.csv` yet: adding a still fixture moves
`PumpPhotoGate`'s measured constants and needs the Vision parser re-measured in the same change,
so they join the still corpus in their own row. Their truth above was read off the key frame by
the orchestrator; the arithmetic closes (45.40 x 1.924 = 87.35, 25.60 x 1.954 = 50.02).
A Live record spans about 1.5 s either side of the key frame, and the camera moves: `live-6229`
and `live-6230` open far from the pump and zoom in. The window quad therefore moves per frame -
fusion must track the key frame's quad through the sequence (feature matching / homography to
the key frame), never assume it is fixed.

Frames are extracted, not committed: `ffmpeg -i live-NNNN.mov -fps_mode passthrough -q:v 2
frames/live-NNNN/%03d.jpg` (`frames/` is gitignored). The first batch (6227-6231) is Dresser Wayne, the second (6237-6262) is Gilbarco; all Circle K
Estonia, daylight. The corpus in `../pump/` stays held-out; these are measurement material for
PU.19 exactly like it.
