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
  (`ml/pump-reader/.venv/bin/pip install boto3`, or any Python with it). `push` also uploads the
  frame JPEGs of every registered record to `pump-live/frames/<record>/` and records each key on
  `frames.s3_key` (the dump does not carry it); `pull --frames <record>` or `pull --frames all`
  fetches them back, and a fresh machine can instead re-extract from the movies with the `ffmpeg`
  line below. `DRY_RUN=1` reports what a push would send without touching the bucket.
- `../pump/` (the still corpus, its annotations and truth) stays in git - the source of truth
  the ratchets read. `push` also uploads a copy of it under `index/`: `corpus.sqlite` (the whole
  corpus as one database - fixtures with truth and size, annotation entries and windows, the
  media with their bucket keys and pairings, the matched pairs) plus the CSVs, `windows.json`,
  the station ledger and this README, so the bucket is a complete copy and not only the bytes git
  refuses. **The database is the write store and the text files are its dump** (`corpus_db.py
  dump` writes them, `corpus_db.py check` fails a stale one); the annotator, `pump_reader.track`
  and the Swift reader all save through it, and `corpus_db.py import` is the one direction back
  from the files. It is committed with the files it dumps (a rebuild from unchanged inputs is
  byte-identical); `scripts/corpus_db.py sql "…"` queries it. Frames regenerate from the movies
  with the `ffmpeg` line below.

Live Photos (HEIC key frame + the paired `.mov`) of pump displays, shared by the product owner on
2026-09-19 for PU.19 (per-cell fusion over frames). Every one is a fill that is ALREADY in
`../pump/`, so the still fixture's `windows.json` entry is the oracle and the still-only score is
the before:

| live | frames | key frame | same fill as | total / liters / unitPrice |
|  | 267 (576x1024, 30 fps, 9.1 s) | Gilbarco Veeder-Root at an Orlen forecourt (, a Verva column beside it), Poland, daylight; **counting up** at ; the owner's own clip, sent as . The source is 13.7 s with 4.6 s of the car's flank and the nozzle in the tank between two display sections (3.6-8.2 s) - cut out and the halves joined, the way video-006 was; the app's  /  tags stripped with the rest | price  constant; 250.73 / 27.89 → ~269.07 / 29.93, then 296.85 / 33.02 → 327.69 / 36.45 (,  close) |
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

## Batch 7 (2026-09-21, product owner): the night set

Eight night stills (`pump-274`..`281`) and two receipts (`receipt-086`/`087`) with their Live
records. The records were lost at the first intake and re-exported by the owner the same evening.

| live | frames | what | paired still / truth |
|---|---|---|---|
| `live-6339` | 70 | Live record of the pump still | `pump-274` |
| `live-6340` | 70 | Live record of the pump still | `pump-275` |
| `live-6341` | 60 | Live record of the pump still | `pump-276` |
| `live-6343` | 83 | Live record of the pump still | `pump-277` |
| `live-6344` | 76 | Live record of the pump still | `pump-278` |
| `live-6345` | 50 | Live record of the receipt | `receipt-086` |
| `live-6346` | 54 | Live record of the pump still | `pump-279` |
| `live-6347` | 62 | Live record of the receipt | `receipt-087` |
| `live-6348` | 73 | Live record of the pump still | `pump-280` |
| `live-6349` | 36 | Live record of the pump still | `pump-281` |

## Batch 6 (2026-09-21, product owner): a morning across Peetri, Olerex and a second Circle K

Thirty-two pump stills and three receipts, every one with its Live record, plus five 4K movies of a
held display and three of a display counting up. The stills are `pump-242`..`pump-273` in `../pump/`
(all **train**, decision 9, windows **pending** - `pendingWindows` in `windows.json` until the owner
draws them), the receipts `receipt-083`..`receipt-085`. Two matched pairs: `pump-248`/`pump-249` with
`receipt-084` (pump 3, 21.43 L) and `pump-253` with `receipt-085` (pump 5, 17.90 L, `EXTRA SOODUS`
-0,36 on the paper). `pump-263` is a **negative**: the Wayne head shows the text `CLOSED` in the
sum window and `-00-` on the board - a reader must commit nothing (product owner). Every Live record
was re-encoded from the phone's `.mov` unchanged; the 4K `.MOV`s had audio and metadata stripped.

| live | frames | what | paired still / truth |
|---|---|---|---|
| `live-6293` | 87 | Live record of the pump still | `pump-242` |
| `live-6294` | 71 | Live record of the pump still | `pump-243` |
| `live-6295` | 57 | Live record of the pump still | `pump-244` |
| `live-6296` | 71 | Live record of the pump still | `pump-245` |
| `live-6297` | 67 | Live record of the pump still | `pump-246` |
| `live-6298` | 89 | Live record of the pump still | `pump-247` |
| `live-6301` | 53 | Live record of the pump still | `pump-248` |
| `live-6302` | 43 | Live record of the pump still | `pump-249` |
| `live-6304` | 87 | Live record of the pump still | `pump-250` |
| `live-6305` | 70 | Live record of the pump still | `pump-251` |
| `live-6306` | 87 | Live record of the pump still | `pump-252` |
| `live-6307` | 86 | Live record of the pump still | `pump-253` |
| `live-6310` | 69 | Live record of the pump still | `pump-254` |
| `live-6311` | 53 | Live record of the pump still | `pump-255` |
| `live-6312` | 87 | Live record of the pump still | `pump-256` |
| `live-6313` | 71 | Live record of the pump still | `pump-257` |
| `live-6314` | 56 | Live record of the pump still | `pump-258` |
| `live-6315` | 85 | Live record of the pump still | `pump-259` |
| `live-6317` | 88 | Live record of the pump still | `pump-260` |
| `live-6318` | 78 | Live record of the pump still | `pump-261` |
| `live-6319` | 52 | Live record of the pump still | `pump-262` |
| `live-6320` | 54 | Live record of the pump still | `pump-263` |
| `live-6321` | 58 | Live record of the pump still | `pump-264` |
| `live-6322` | 76 | Live record of the pump still | `pump-265` |
| `live-6324` | 59 | Live record of the pump still | `pump-266` |
| `live-6325` | 77 | Live record of the pump still | `pump-267` |
| `live-6326` | 46 | Live record of the pump still | `pump-268` |
| `live-6327` | 50 | Live record of the pump still | `pump-269` |
| `live-6330` | 86 | Live record of the pump still | `pump-270` |
| `live-6332` | 85 | Live record of the pump still | `pump-271` |
| `live-6333` | 83 | Live record of the pump still | `pump-272` |
| `live-6334` | 67 | Live record of the pump still | `pump-273` |
| `live-6300` | 57 | Live record of the receipt | `receipt-083` |
| `live-6303` | 54 | Live record of the receipt | `receipt-084` |
| `live-6308` | 88 | Live record of the receipt | `receipt-085` |
| `live-6299` | 158 | 4K movie, held display, moving angle | `pump-247` - 0069,99 / 0036,47 at 1,919 |
| `live-6309` | 147 | 4K movie, held display, moving angle | `pump-253` - 0035,07 / 0017,90 at 1,959, glare |
| `live-6316` | 146 | 4K movie, held display, moving angle | `pump-259` - 0131,94 / 0062,86 at 2,099 |
| `live-6323` | 77 | 4K movie, held display, moving angle | `pump-264` - 55.40 / 28.87, Wayne board |
| `live-6331` | 189 | 4K movie, held display, moving angle | `pump-270` - 0063,27 / 0031,97 at 1,979 |

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

| `video-010-gilbarco-veederroot-running-display-social-third-party-ru` | 334 (360x640, 30 fps, 11 s) | Gilbarco Veeder-Root, RU, a social-media clip pasted by the product owner - **third-party**, a caption overlay at the bottom (not over the display), the camera walks to the nozzle and back | price `66,10` constant; 605 → 797,83 / 12,09; the display 8-10 % of a 360 px frame - the smallest display material in the corpus |

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

## Batch 8 (2026-09-20, product owner): ten more running displays - India, Russia x4, Kazakhstan x2, Belarus, Estonia, Poland

Same medium and the same cut as Batch 5: only the seconds that show the display, no audio, no
metadata. Every clip is second-hand (a YouTube short, four social-media clips the owner
forwarded); frames extract with `pump_reader.frames`, quads come from one hand-placed reference
frame in `videos.json` and `pump_reader.track --videos` carries them through the clip.

| video | frames | what | truth |
|---|---|---|---|
| `video-005-unknown-running-display-fill-ends-inr-in` | 938 (1080x1920, 25 fps, 37.5 s) | Indian petrol pump (make unreadable; three separate LCD windows, `PETROL` on the skirt), **display counting up and then holding** - the last ~4 s show the final state; the 10 s of nozzle-in-tank before the display and the pan to a person after it were cut | price `103.03` constant; total/liters run 1345.57 / 13.06 → 1701.02 / 16.51 (`14.37 x 103.03 = 1480.54`, `14.71 x 103.03 = 1515.57` close). **This display truncates the total, it does not round**: `15.61 x 103.03 = 1608.298` shows `1608.29`, `16.51 x 103.03 = 1701.025` shows `1701.02` - the arithmetic label's tolerance (`PumpVideoReadTests`, 0.011) still accepts it. Source: `youtube.com/shorts/wSIqP3heiaE`; 45 opening frames drop from tracking (the pan-in blur) |
| `video-006-shelf-running-display-preset-ends-ru` | 294 (720x1280, 30 fps, 9.8 s) | Shelf dispenser, Russia (`ПСБ` / `МИР` badges, `Стоимость` / `Объем` / `Цена за 1л.`), shot from a car window far from the pump so the digits are small; **counting up, then jumping to the preset end** `8000.00 / 50.00` - the poster's own jump cut. The 5.75 s of car flank and the owner's hand between the two display sections were cut out and the halves joined; a caption `зато не пешком` and a date are burned in at the foot | price `160.00` constant; 3678.40 / 22.99 → 4332.80 / 27.08, then 8000.00 / 50.00 (`22.99 x 160 = 3678.40`, `26.48 x 160 = 4236.80`, `27.08 x 160 = 4332.80`, `50 x 160 = 8000` close) |
| `video-008-gilbarco-veederroot-running-display-ru` | 595 (576x1024, 30 fps, 19.8 s) | Gilbarco Veeder-Root, Russia (`РУБЛИ` / `ЛИТРЫ` / `ЦЕНА/ЛИТР`; the same head as the Gilbarco Veeder-Root Cyrillic stills in `../pump/README.md`, not the same fill), **counting up** through a fill; the poster's EUR/USD caption box is burned in below the display; the first 2 s (the columns, no display) were cut | price `63,25` constant; 132.19 / 2.09 → 909.54 / 14.38 (`3.67 x 63.25 = 232.13`, `3.32 x 63.25 = 209.99`, `14.38 x 63.25 = 909.54` close) |
| `video-009-adast-running-display-slow-fill-kz` | 300 (720x1280, 30 fps, 10 s) | ADAST, Kazakhstan (Kazakh caption `Шөлдеп қапты` burned in), three-row LCD (`СУММА` / `ЛИТРЫ` / `ЦЕНА/ЛИТР`), camera close and steady, a **slow** fill - 0.36 L in 10 s; the pan to the driver after 10 s was cut | price `233` constant; 14935 / 64.10 → 15019 / 64.46 (`64.10 x 233 = 14935.3`, `64.36 x 233 = 14995.9` shows `14996`, `64.46 x 233 = 15019.2` close - this one rounds) |
| `video-011-gilbarco-veederroot-lukoil-zero-padded-running-display-ru` | 60 (576x1024, 30 fps, 2 s) | Gilbarco Veeder-Root at Lukoil (`ЭКТО` column labels), Russia - the **zero-padded** face (`01719.88` / `0027.14` / `063.44`; the same face as the zero-padded Lukoil still in `../pump/README.md`, not the same fill), **counting up**; the owner asked for the first 2 s only, the rest of the clip pans off the display | price `063,44` constant; ~1710 / 26.9 → ~1800 / 28.0 (`27.14 x 63.44 = 1721.8`; the frames are soft, read to the litre only) |
| `video-012-wayne-gazpromneft-running-display-by` | 450 (1080x1920, 30 fps, 15 s) | Wayne at Gazpromneft (`G-Drive` / `92` chips, `СУММА` / `ЛИТР` / `ЦЕНА ЗА ЛИТР`), Belarus - BYN, **counting up** in a close-up that zooms out over 7 s; from 7 s the poster cuts to a wide shot of the forecourt's other pumps (a different fill, the display 20 px tall), which the tracker drops (243 of 450 frames); the owner asked for the first 15 s | price `2.58` constant; 4.02 / 1.56 → 13.44 / 5.21 (`1.56 x 2.58 = 4.02`, `3.39 x 2.58 = 8.75`, `5.21 x 2.58 = 13.44` close). Source: `youtube.com/shorts/ndmr_q3XOnk` |
| `video-013-unknown-cent-per-liter-zero-padded-running-display-ee` | 60 (720x1280, 30 fps, 2 s) | The `€` / `Liter` / `Cent/Liter` face (Estonia by the labels, make unreadable), **zero-padded** to four integer digits (`0020,02` / `0010,59`), the camera close and tilted ~8 degrees so the leading zeros run off the left edge of every frame; a poster's caption box top-right and a cartoon at the foot (a drawing, not a person); the owner asked for the last 2 s of the short | price `189,9` cents constant; 19.94 / 10.50 → 20.96 / 11.04 (`10.50 x 1.899 = 19.94`, `11.04 x 1.899 = 20.96` close). Source: `youtube.com/shorts/dQwQZAdoTsU` |
| `video-014-adast-night-running-display-lpg-pl` | 1500 (2160x3840, 60 fps, 25 s) | ADAST, Poland (`zł` / `L` / `zł / L`), **at night**, the backlit LCD the only bright thing in the frame - the segments render in colour fringes (blue/yellow) on the 4K sensor; **counting up** through an LPG fill at 2.95 zł/L, the camera walking the angle; the owner asked for 10-35 s of the short (the display lights at ~11 s) | price `2.95` constant; 0.86 / 0.29 → ~23.1 / 7.83 (`2.85 x 2.95 = 8.41`, `5.42 x 2.95 = 15.99`, `7.53 x 2.95 = 22.21` close). Source: `youtube.com/shorts/aYYiQl--ulk`; 62 frames drop (the dark opening before the display fills the frame) |
| `video-015-wayne-nnk-walk-in-three-decimal-liters-running-display-ru` | 120 (1080x1920, 30 fps, 4 s) | Wayne at ННК (Khabarovsk region by the `Кофе на ННК` stand), Russia, diesel at `63.03` - the **three-decimal litres** face (`49.517 ЛИТРЫ`); the camera walks in from ~4 m, so the display is legible only in the last second; the owner asked for the first 4 s | price `63.03` constant; ~2964 / 47.04 → 3121.06 / 49.517 (`49.517 x 63.03 = 3121.06` closes to the cent). Source: `youtube.com/shorts/EuN1C2jC6uc`. **Finding:** the tracker keeps only the last 19 of 120 frames - registration from the close reference frame to the far ones fails on scale (`< 30` inliers), the same shape as the zoom-in Live records' lost openings |
| `video-016-topaz-gdrive-gazpromneft-running-display-ru` | 63 (1920x1080, 25 fps, 2.5 s) | Topaz at a G-Drive column, Russia, daylight, the display **counting up** through an AI-95 fill at `69.59`; the owner asked for 43-47 s of the source, the display fills the frame from 44.5 s and a presenter walks in at 47 s, so the cut is 44.4-46.9 s. `../pump/pump-231` is a frame of it | price `69.59` constant; ~2573 / 36.98 → 2590.84 / 37.23 (`37.23 x 69.59 = 2590.84` closes). Source: `youtube.com/watch?v=_wpWcl6Mhzw` |
| `video-017-topaz-clip-caption-running-display-ru` | 140 (1080x1920, VFR ~20 fps, 7 s) | Topaz, Russia, a vertical clip with a QR top-left and a red `КАЖДЫЙ ЛИТР ИМЕЕТ ЗНАЧЕНИЕ` caption band that grows in over the first 3 s; **counting up** at `69.41`; cut before the logo card at 7 s. `../pump/pump-234` is a 360 px frame of it | price `69.41` constant; 409.52 / 5.90 → ~701.74 / 10.11 (`5.97 x 69.41 = 414.38`, `10.11 x 69.41 = 701.73` close). Source: VK clip `-204527792_456239354` (permpoisk) | **Finding (2026-09-21):** the burned-in QR and caption band matched the anchor at the identity in every frame and, being ~2 900 keypoints, outvoted the moving display in RANSAC - all 140 frames came back as copies of the reference with 1 700-2 500 "inliers". `pump_reader.track` now drops an anchor keypoint whose match sits within 3 px of itself in most of the frames it matches (`Registrar.drop_static`); a still camera keeps everything. With that and a second anchor at `125.jpg` (placed by the orchestrator, unreviewed) the zoom tracks to the end. The owner's anchor at `001.jpg` carries the liters quad on the price window - anchoring writes all three quads, so a drag of one quad also freezes the other two where the bad track left them
| `video-018-tokheim-winter-clip-caption-running-display-ru` | 548 (720x1280, 30 fps, 18.5 s) | Tokheim (`Стоимость` / `Количество` / `Цена за 1 литр`), Russia, winter dusk, the same caption band and QR as video-017, the digits small in frame; **counting up** the whole clip at `67.06` | price `67.06` constant; 17.44 / 0.26 → ~669.7 / 9.98 (`3.19 x 67.06 = 213.92`, `9.98 x 67.06 = 669.26` close). Source: VK clip `-204527792_456239281` (permpoisk) |
| `video-019-gilbarco-veederroot-orlen-cutaway-running-display-pl` | 267 (576x1024, 30 fps, 9.1 s) | Gilbarco Veeder-Root at an Orlen forecourt (`STANOWISKO 5`, a Verva column beside it), Poland, daylight; **counting up** at `8,99 zł/L`; the owner's own clip, sent as `IMG_18166.mp4`. The source is 13.7 s with 4.6 s of the car's flank and the nozzle in the tank between two display sections (3.6-8.2 s) - cut out and the halves joined, the way video-006 was; the app's `aigc_info` / `vid:` tags stripped with the rest | price `8.99` constant; 250.73 / 27.89 → ~269.07 / 29.93, then 296.85 / 33.02 → 327.69 / 36.45 (`27.89 x 8.99 = 250.73`, `36.45 x 8.99 = 327.69` close) |
| `video-020-unknown-petro-held-display-dm3-third-party-pl` | 114 (1072x1906, 30 fps, 3.8 s) | A Polish dispenser (make not on the face; `PETRO` badge top-left, `LICZYDŁO POWINNO WSKAZYWAĆ ZERO`), the **dm³ face** - `zł` / `dm³` / `zł/dm³` - **held** at the fill's end: `410,07` / `44,67` at `9,18`, the camera drifting closer under glare; the 5.8 s pan to the nozzle rack after it was cut. **Third-party** (a Facebook video the owner linked; yt-dlp reads facebook.com without a login) | price `9.18` constant; static `410.07 / 44.67` (`44.67 x 9.18 = 410.07` closes) |
| `video-021-wayne-orlen-held-display-price-unlit-pl` | 178 (1080x1920, 60 fps, 3 s) | Dresser Wayne at an Orlen forecourt (`1`, an `mFLOTA ORLEN` sticker), Poland, daylight, the dm³ face **held** at `463,72 zł` / `55,27 dm³` with the **price window unlit** - no `unitPrice` window; the constant `8.39` is the quotient (463.72 / 55.27 = 8.3902 and 55.27 x 8.39 = 463.72 exactly), not a read. The owner's own clip (`IMG_55151.mp4`, 50 s); the owner asked for the last 3 s | price `8.39` (inferred); static `463.72 / 55.27` |
| `video-022-gilbarco-veederroot-orlen-caption-diesel-running-display-pl` | 175 (544x968, 30 fps, 5.8 s) | Gilbarco Veeder-Root at an Orlen forecourt (`STANOWISKO 1`, a `ZACHOWAJ BEZPIECZEŃSTWO` sign), Poland, daylight, the **zero-padded** face (`0305,25` / `0034,53` at `08,84`), a diesel fill **counting up**, a white caption `Tak brzmi tankowanie diesela do pełna` burned in at the foot; the owner's own clip (`IMG_27747.mp4`), the first 3 s of car and nozzle cut as asked | price `8.84` constant; ~233.6 / 26.4 → 331.99 / 37.55 (`34.53 x 8.84 = 305.25` closes) |
| `video-023-gilbarco-veederroot-orlen-night-oblique-running-display-pl` | 180 (720x1280, 30 fps, 6 s) | Gilbarco Veeder-Root at an Orlen forecourt (`STANOWISKO 3`, Verva columns), Poland, **at night**, the head shot **obliquely from the left** so the digits are small and skewed; **counting up** at `7,34`; the owner asked for 6-12 s of a 21.6 s clip (a pan along the nozzle rack before it) | price `7.34` constant; ~148 / 20.2 → 221.7 / 30.2 (`29.44 x 7.34 = 216.09` closes) |
| `video-024-unknown-bucees-gallons-meme-caption-running-display-us` | 424 (720x1280, 30 fps, 14.1 s) | A Buc-ee's diesel dispenser (make not on the face), USA, `This Sale $` / `Gallons`, **three-decimal gallons** counting up through a diesel fill; a green `DIESEL PUMPS BE LIKE` meme caption burned in below the display and the pump-number card above; whole clip kept (no person). No price window on this face: `unitPrice` is the quotient **5.999 $/gal** (141.92 / 23.657; every sampled pair closes on it) and `volumeUnit: gal` says the `liters` field carries gallons - the arithmetic gate is unit-agnostic. Sent by the owner as `IMG_22610.mp4`; the corpus's first US clip | price `5.999` (inferred); 135.78 / 22.631 → 148.57 / 24.766 (`23.657 x 5.999 = 141.92` closes) |
| `video-025-wayne-olerex-tankur2-running-display-ee` | 337 (2160x3840, 24 fps, 14 s) | Dresser Wayne at Olerex TANKUR 2 (`EUR` / `LIITRIT` / `EUR/1L`, `Tb = 15°C`), Estonia, daylight, **counting up** through a petrol fill at `1.884`; the owner's own 4K clip (`IMG_6328.MOV`), whole clip kept. Idle heads of the same station: `../pump/pump-268`, `pump-269` | price `1.884` constant; ~21.4 / 11.4 → 29.6 / 15.7 (`13.80 x 1.884 = 26.00` closes) |
| `video-026-wayne-olerex-tankur6-running-display-ee` | 368 (3840x2160, 24 fps, 15 s) | The same Olerex face at TANKUR 6, landscape, **counting up** through a diesel fill at `2.109` from 6.69 / 3.55 (`IMG_6329.MOV`, whole clip) | price `2.109` constant; 6.69 / 3.55 → ~24.9 / 11.8 (`8.33 x 2.109 = 17.57` closes) |
| `video-027-gilbarco-circlek-five-grade-pump2-running-display-ee` | 670 (3840x2160, 24 fps, 28 s) | Gilbarco Veeder-Root at the second Circle K (the five-grade board down the left: 1.919 / 1.969 / 1.979 / 2.132 / 2.232), pump 2, **counting up** through a 95 miles+ fill at `1.969` (`IMG_6335.MOV`, whole clip); the still `../pump/pump-273` is a later fill on the same head at 1.919 | price `1.969` constant; 13.04 / 6.80 → 32.31 / 16.84 (`17.88 x 1.969 = 35.21` closes) |

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
implausibly. It saves the record through `corpus_db.save_tracked`, which dumps
`frames/<stem>/windows.json` (the corpus shape, keyed by frame, with the
still's `field` / `text` / `legibility`) and writes `frames/<stem>/sheet.jpg` with the quads drawn -
the one human step is a glance at the sheet, or the annotator's Frames view. Every paired
record is tracked so the annotator can show any of them; the output carries the still's
`split`, and **only train records feed the glyph extractor** (decision 9) - a heldout still's
frames are the same fill and never train. Run of 2026-09-20: **63 records, 2 766 frames kept,
506 dropped** (the drops are the far, blurred opening frames of the zoom-in records and
`live-6227`, the plain video whose framing never matches its still); 46 of the records, 1 906
frames, are train. Every kept frame carries the still's text as its label - the raw material of
`pump_reader.realglyphs`.
