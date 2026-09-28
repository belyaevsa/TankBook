# PU.91 round 2 - frames to verify (2026-09-28)

Model `seg-r2` against the tracker, one frame in three of every dark-display record. For each record: the frames where the
model and the tracked boxes disagree most (worst window IoU, a row the tracker lacks), spread at least 6 frames apart, then a
few frames where they agree, for spread. Open the record in the annotator, **go to** the frame number, fix the boxes if they are
wrong and save it verified. Frame numbers are 1-based, as **go to** takes them.

| record | scored | agree | verify (worst first) | spot-check (agreeing) |
|---|---|---|---|---|
| `live-6339` | 24 | 23 | 64 | 1, 10, 19, 28, 37, 46 |
| `live-6340` | 24 | 24 | – | 1, 13, 25, 37, 49, 61 |
| `live-6341` | 20 | 13 | 2, 18, 12, 54 | 15, 21, 27, 33, 39, 45 |
| `live-6343` | 28 | 26 | 67, 73 | 1, 13, 25, 37, 49, 61 |
| `live-6344` | 26 | 26 | – | 1, 13, 25, 37, 49, 61 |
| `live-6346` | 17 | 16 | – | 1, 8, 17, 23, 29, 35 |
| `live-6348` | 25 | 25 | – | 1, 13, 25, 37, 49, 61 |
| `live-6349` | 12 | 12 | – | 1, 7, 13, 19, 25, 31 |
| `live-6397` | 27 | 20 | 25, 1, 64, 79, 19 | 7, 16, 28, 37, 46, 55 |
| `live-6398` | 29 | 0 | 1, 7, 13, 19, 25, 31, 37, 43, 73, 52, 79, 67, 85, 61 | – |
| `live-6399` | 29 | 0 | 31, 22, 46, 10, 1, 64, 16, 52, 37, 79, 85, 73, 58 | – |
| `live-6402` | 30 | 22 | 82, 25, 31, 88, 43, 7 | 1, 10, 19, 28, 37, 49 |
| `live-6403` | 25 | 25 | – | 1, 13, 25, 37, 49, 61 |
| `live-6404` | 20 | 13 | 59, 43, 28, 52 | 4, 10, 16, 22, 31, 37 |
| `live-6405` | 29 | 8 | 19, 58, 79, 25, 7, 13, 70, 1, 43, 49 | 4, 28, 52, 61, 87 |
| `live-6420` | 21 | 20 | 1 | 4, 13, 22, 31, 40, 49 |
| `live-6424` | 19 | 1 | 25, 49, 1, 10, 31, 55, 16, 40 | 46 |
| `live-6425` | 22 | 12 | 64, 4, 19, 13, 52, 25 | 1, 28, 34, 40, 46, 55 |
| `live-6432` | 18 | 18 | – | 15, 24, 33, 42, 51, 60 |
| `live-6433` | 13 | 10 | 37, 31 | 1, 7, 13, 19, 25 |
| `live-6434` | 11 | 7 | 4, 19 | 10, 16, 22, 28 |
| `live-6455` | 19 | 16 | 39 | 18, 24, 30, 36, 42, 48 |
| `live-6457` | 21 | 21 | – | 1, 10, 19, 28, 37, 46 |
| `live-6458` | 8 | 5 | 45 | 27, 33, 39 |
| `video-014-adast-night-running-display-lpg-pl` | 478 | 341 | 790, 34, 628, 845, 585, 601, 465, 477, 555, 567, 1496, 408, 390, 1469, 1484, 342, 177, 375, 420, 327, 360, 1424, 1478, 1490, 1436, 312, 303, 348, 160, 498 | 42, 213, 381, 549, 718, 887 |
| `video-023-gilbarco-veederroot-orlen-night-oblique-running-display-pl` | 51 | 18 | 27, 33, 39, 45, 51, 57, 63, 69, 75, 81, 105, 114, 120, 126, 132, 141, 157, 166, 172, 178 | 84, 93, 102, 111, 135, 147 |
| `video-050-unknown-alexela-black-lcd-running-display-2079-ee` | 313 | 166 | 645, 327, 63, 297, 303, 312, 333, 339, 621, 633, 639, 651, 657, 663, 45, 75, 81, 87, 669, 675, 681, 687, 69, 123, 696, 888, 228, 222, 180, 423 | 2, 90, 171, 252, 348, 429 |
| `video-051-tokheim-terminal-tft-static-display-2080-ee` | 44 | 39 | 110, 125, 116 | 1, 19, 37, 55, 74, 92 |
| `video-052-unknown-alexela-black-lcd-running-display-2059-ee` | 520 | 425 | 61, 70, 94, 130, 648, 663, 900, 359, 560, 270, 276, 627, 1026, 285, 633, 609, 1281, 729, 1515, 657, 954, 774, 1233, 960, 741, 1089, 1290, 1, 294, 300 | 4, 217, 428, 639, 849, 1059 |
| `video-053-tokheim-olerex-peetri-tft-running-display-2039-ee` | 155 | 63 | 226, 1, 7, 13, 19, 25, 49, 175, 181, 187, 196, 205, 214, 220, 232, 238, 244, 253, 259, 109, 76, 145, 67, 43, 136, 124, 118, 85, 361, 367 | 31, 61, 154, 199, 229, 262 |

379 frames in all. After they are saved verified, round 3 is `segdata` -> `segtrain` -> `segeval` -> `segdisagree` again.
