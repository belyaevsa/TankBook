# Live Photo pump captures

**Where the media lives (product owner, 2026-09-19): Yandex Object Storage, not git.** The
`.mov` and `.heic` files are gitignored; this README and its pairing tables are the record.

## Access

- Bucket `tankbook-corpus` (S3-compatible endpoint `https://storage.yandexcloud.net`, region
  `ru-central1`), prefix `pump-live/`. Private; nothing in it is public.
- Read/write is through the service account `tankbook-corpus-rw` with a **static access key**.
  Keys are never in the repo (`docs/SECURITY.md`); each person mints their own:
  `yc iam access-key create --service-account-name tankbook-corpus-rw --format json`
  (needs `yc init` against the Tankbook folder first) and writes the two values to
  `~/.config/tankbook/corpus-s3.env` as `AWS_ACCESS_KEY_ID=…` / `AWS_SECRET_ACCESS_KEY=…`
  (mode 600). Revoke a key with `yc iam access-key delete`.
- Sync: `scripts/corpus-sync.py pull` (a fresh machine), `push` (after new captures land),
  `list`. It compares size and MD5, so a re-run moves nothing already there. Needs `boto3`
  (`ml/pump-reader/.venv/bin/pip install boto3`, or any Python with it).
- `../pump/` (the still corpus, its annotations and truth) stays in git - the source of truth
  the ratchets read. `push` also uploads a copy of it under `index/`: `corpus.sqlite` (the whole
  corpus as one database, built by `scripts/corpus_db.py` - fixtures with truth and size,
  annotation entries and windows, the media with their bucket keys and pairings, the matched
  pairs) plus the CSVs, `windows.json`, the station ledger and this README, so the bucket is a
  complete copy and not only the bytes git refuses. The database is derived;
  `scripts/corpus_db.py build` rebuilds it, `tools/pump-annotate` rebuilds it on every save, and it is committed with the files it is built from (a rebuild from unchanged inputs is byte-identical);
  `scripts/corpus_db.py sql "…"` queries it. Frames regenerate from the movies with the
  `ffmpeg` line below.

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


## Batch 3 (2026-09-19): Live records of the existing corpus stills

The product owner shared the Live Photos behind the corpus's own stills. The HEIC key frames were
copies of fixtures already in `../pump/` (64 matched by perceptual hash at distance 0, the rest the
same fills at another framing, read by eye) and were removed; only the `.mov` records are kept, so
each row below is a frame sequence for a still fixture that already has its `windows.json`
annotation - the fusion row (PU.19) scores the fused read against the still's truth. Frames extract
as above; `frames/` is gitignored.

| live | frames | paired still | note |
|---|---|---|---|
| `live-5844` | 58 | pump-001 |  |
| `live-5860` | 53 | pump-011 |  |
| `live-5861` | 74 | pump-012 |  |
| `live-5864` | 43 | pump-013 |  |
| `live-5865` | 54 | pump-014 |  |
| `live-5866` | 55 | pump-015 |  |
| `live-5867` | 54 | pump-016 |  |
| `live-5868` | 27 | pump-017 |  |
| `live-5876` | 48 | pump-019 |  |
| `live-5878` | 36 | pump-020 |  |
| `live-5880` | 37 | pump-021 |  |
| `live-5881` | 61 | pump-022 |  |
| `live-5882` | 52 | pump-023 |  |
| `live-5883` | 59 | pump-024 |  |
| `live-5884` | 59 | pump-025 |  |
| `live-5890` | 52 | pump-026 |  |
| `live-5891` | 55 | pump-027 |  |
| `live-5892` | 56 | pump-028 |  |
| `live-5909` | 65 | pump-031 |  |
| `live-5911` | 47 | unpaired |  |
| `live-5912` | 39 | pump-032 |  |
| `live-5913` | 64 | pump-033 |  |
| `live-5914` | 35 | pump-034 |  |
| `live-5916` | 0 | pump-035 |  |
| `live-5917` | 39 | pump-036 |  |
| `live-5918` | 22 | unpaired |  |
| `live-5928` | 55 | pump-038 |  |
| `live-5932` | 58 | pump-039 |  |
| `live-5933` | 52 | unpaired |  |
| `live-5937` | 24 | unpaired |  |
| `live-5938` | 52 | pump-046 |  |
| `live-5939` | 28 | pump-047 |  |
| `live-5943` | 80 | unpaired |  |
| `live-5944` | 64 | pump-049 |  |
| `live-5945` | 53 | unpaired |  |
| `live-5947` | 53 | unpaired |  |
| `live-5948` | 37 | pump-053 |  |
| `live-5949` | 50 | unpaired |  |
| `live-5951` | 53 | pump-055 |  |
| `live-5952` | 57 | unpaired |  |
| `live-5968` | 53 | pump-057 |  |
| `live-5970` | 81 | unpaired |  |
| `live-5971` | 50 | pump-059 |  |
| `live-5972` | 36 | pump-060 |  |
| `live-5973` | 48 | pump-061 |  |
| `live-5974` | 86 | unpaired |  |
| `live-5975` | 58 | unpaired |  |
| `live-5976` | 55 | pump-064 |  |
| `live-6013` | 41 | unpaired |  |
| `live-6014` | 49 | unpaired |  |
| `live-6015` | 24 | unpaired |  |
| `live-6016` | 62 | unpaired |  |
| `live-6018` | 56 | unpaired |  |
| `live-6019` | 53 | unpaired |  |
| `live-6020` | 64 | pump-067 |  |
| `live-6022` | 55 | pump-068 |  |
| `live-6024` | 53 | unpaired |  |
| `live-6041` | 43 | pump-077 |  |
| `live-6043` | 37 | pump-075 |  |
| `live-6044` | 41 | pump-076 |  |
| `live-6049` | 33 | pump-078 |  |
| `live-6051` | 28 | pump-079 |  |
| `live-6052` | 26 | unpaired |  |
| `live-6053` | 53 | pump-081 |  |
| `live-6054` | 87 | pump-082 |  |
| `live-6228` | 32 | pump-097 | duplicate of an existing live capture, dropped |
| `live-6229` | 53 | pump-098 | duplicate of an existing live capture, dropped |
| `live-6230` | 48 | pump-099 | duplicate of an existing live capture, dropped |
| `live-6231` | 57 | pump-100 | duplicate of an existing live capture, dropped |
| `live-6237` | 50 | pump-101 | duplicate of an existing live capture, dropped |
| `live-6238` | 35 | pump-102 | duplicate of an existing live capture, dropped |
| `live-6239` | 33 | unpaired | duplicate of an existing live capture, dropped |
| `live-6240` | 68 | unpaired | duplicate of an existing live capture, dropped |
| `live-6242` | 42 | pump-105 | duplicate of an existing live capture, dropped |
| `live-6245` | 24 | new fill (already in pump-live) | duplicate of an existing live capture, dropped |
| `live-6246` | 48 | new fill (already in pump-live) | duplicate of an existing live capture, dropped |
| `live-6227` | 24 | plain video, unpaired | |

## Batch 4 (2026-09-19, product owner): two pump/receipt pairs, three movies with angle and flicker

Two fills captured every way at once - the still (now `pump-115`/`pump-116` in `../pump/`, EXIF
stripped, JPEG), the receipt (`receipt-074`/`receipt-075` in `../receipts/`), a Live record of each,
and a longer 4K video walking the angle with the LCD flickering; plus a third fill on video only.

| live | frames | what | paired still / truth |
|---|---|---|---|
| `live-6281` | 51 | Live record of the pump still | `pump-115` - 30.02 / 15.17 / 1.979 |
| `live-6282` | 80 | Live record of the receipt | `receipt-074` (same fill) |
| `live-6280` | 71 | 4K video, moving angle, flicker | `pump-115` (same fill) |
| `live-6283` | 43 | Live record of the pump still | `pump-116` - 55.13 / 27.86 / 1.979 |
| `live-6284` | 56 | Live record of the receipt | `receipt-075` (same fill) |
| `live-6285` | 224 | 4K video, moving angle, flicker | `pump-116` (same fill) |
| `live-6279` | 149 | 4K video, moving angle, flicker | **new fill, video only** - 62.12 / 32.37 / 1.919 (read by eye from the frames) |

## Batch 5 (2026-09-19, product owner): a running display on video

`video-NNN-…mp4` is a third kind of medium beside the Live records: a plain video, not from
the owner's camera roll, cut down to the seconds that show the display. The source clip here
was 32 s of which the pump fills the frame for the first 7; the rest shows a person's face and
was **not kept** - the file in the bucket is the 7 s cut, re-encoded without audio or metadata.

| video | frames | what | truth |
|---|---|---|---|
| `video-001-wayne-circlek-running-display-ee` | 210 (720x1280, 30 fps) | Dresser Wayne, Circle K EE, **display counting up while pumping** | price `1.729` constant; total/liters run 3.18 / 1.84 → 4.98 / 2.88. Read at 1 fps by the orchestrator: 3.32/1.92, 3.73/2.16, 3.94/2.28, 4.27/2.47, 4.51/2.61, 4.88/2.82, 4.96/2.87 - every pair closes (`round(L x 1.729, 2)`) |

| `video-002-wayne-running-display-slow-fill-ru` | 1184 (1280x720, 29 fps, 41 s) | Wayne, Russia, **display counting up** through a slow diesel fill, camera steady, whole clip kept (no person in frame) | price `73.60` constant; total/liters run 2314.72 / 31.45 → 2475.17 / 33.63 (`31.45 x 73.60 = 2314.72` closes). Second-hand clip, third-party |

| `video-003-wayne-circlek-fill-ends-ee` | 1209 (576x1024, 30 fps, 40 s) | Wayne, Circle K EE, **display counting up and then stopping** - the last ~4 s hold 155.48 / 75.51, the transaction's final state | price `2.059` constant; 146.89 / 71.34 → 155.48 / 75.51 (`75.51 x 2.059 = 155.48` closes). The one clip that shows the moment a fill becomes a transaction; second-hand, third-party |

## Batch 6 (2026-09-20, product owner): one Live record

| live | frames | paired still | note |
|---|---|---|---|
| `live-4386` | 73 (1920x1440) | `pump-212` | Dresser Wayne, Circle K EE; the HEIC became the still |

| `video-005-gilbarco-veederroot-running-display-social-third-party-ru` | 334 (360x640, 30 fps, 11 s) | Gilbarco Veeder-Root, RU, a social-media clip pasted by the product owner - **third-party**, a caption overlay at the bottom (not over the display), the camera walks to the nozzle and back | price `66,10` constant; 605 → 797,83 / 12,09; the display 8-10 % of a 360 px frame - the smallest display material in the corpus |

Why it is worth having: every frame shows a *different* number, so there is no single truth
row - but the display's own arithmetic is a per-frame oracle for free: a frame's reading is
right when `total == round(liters x 1.729, 2)`. That is a self-check no still can offer and the
material for the running-display behaviour (`docs/EXTRACTION.md`: a pump mid-fill is not a
transaction until the numbers stop). Frames extract with the `ffmpeg` line above.

## Batch 7 (2026-09-20, product owner): a second running display, Cyrillic head

Same kind of medium as Batch 5, cut the same way (the 4.5 s forecourt pan removed, no audio, no
metadata); the still cousins of this head are `pump-214`..`pump-216`.

| video | frames | what | truth |
|---|---|---|---|
| `video-004-gilbarco-veederroot-running-display-fill-ends-som-kg` | 1407 (720x1280, 30 fps, 46.9 s) | Gilbarco Veeder-Root, Kyrgyzstan (`СОМ`, `ЦЕНА ЗА 1 ЛИТР`), **display counting up through a 66 L diesel fill and then holding** - the last 5.5 s show the final state; a 4.5 s pan to the forecourt (a car, no display) was cut out and the two halves joined; a person's back is in the lower frame throughout, no face | price `99,9` constant; total/liters run 2955.04 / 29.58 → 6618.38 / 66.25 (`29.58 x 99.9 = 2955.04`, `66.25 x 99.9 = 6618.38` close). Read at 5 s steps by the orchestrator: 3356.64/33.60, 3763.23/37.67, 4155.84/41.60, 4562.43/45.67, 4962.03/49.67, 5361.63/53.67, 5762.23/57.68, 6155.84/61.62. Owner-sourced, second-hand (a caption `Дизель 100 сом за литр` is burned in for the first seconds) |

## Frames and tracking (2026-09-20)

Two scripts in `ml/pump-reader` turn the records into labelled training frames without a
single new annotation:

```
cd ml/pump-reader
PYTHONPATH=src .venv/bin/python -m pump_reader.frames        # every movie -> frames/<stem>/NNN.jpg
PYTHONPATH=src .venv/bin/python -m pump_reader.track         # the still's quads carried into its record
```

`frames` extracts all 92 movies (7 214 frames, 1.4 GB, gitignored, regenerates in minutes).
`track` registers each frame to its paired still directly - ORB on the display region, RANSAC
homography, never chained frame to frame - maps the still's quads through it and drops a frame
whose registration is weak (< 30 inliers) or whose quads leave the image or change area
implausibly. It writes `frames/<stem>/windows.json` (the corpus shape, keyed by frame, with the
still's `field` / `text` / `legibility`) and `frames/<stem>/sheet.jpg` with the quads drawn -
the one human step is a glance at the sheet, or the annotator's Frames view. Every paired
record is tracked so the annotator can show any of them; the output carries the still's
`split`, and **only train records feed the glyph extractor** (decision 9) - a heldout still's
frames are the same fill and never train. Run of 2026-09-20: **63 records, 2 766 frames kept,
506 dropped** (the drops are the far, blurred opening frames of the zoom-in records and
`live-6227`, the plain video whose framing never matches its still); 46 of the records, 1 906
frames, are train. Every kept frame carries the still's text as its label - the raw material of
`pump_reader.realglyphs`.
