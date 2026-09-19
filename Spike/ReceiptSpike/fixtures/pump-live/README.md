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

A Live record spans about 1.5 s either side of the key frame, and the camera moves: `live-6229`
and `live-6230` open far from the pump and zoom in. The window quad therefore moves per frame -
fusion must track the key frame's quad through the sequence (feature matching / homography to
the key frame), never assume it is fixed.

Frames are extracted, not committed: `ffmpeg -i live-NNNN.mov -fps_mode passthrough -q:v 2
frames/live-NNNN/%03d.jpg` (`frames/` is gitignored). All from Circle K Estonia, Dresser Wayne
heads, daylight. The corpus in `../pump/` stays held-out; these are measurement material for
PU.19 exactly like it.
