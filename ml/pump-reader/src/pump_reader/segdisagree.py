"""CLI: ``python -m pump_reader.segdisagree --run .out/seg-r2 [--compare .out/seg-r1] [--step 3]``.

Where a trained row segmenter and the tracker disagree, per frame of the
records the owner verifies next (PU.91's loop). The tracker carries the still's
or the reference frame's hand quads into every frame and drifts (PU.66), which
is why `segdata` trains on verified frames only; a model's boxes drift
differently. A frame where the two agree is probably right in both; a frame
where they disagree is the one worth the owner's look.

For every tracked, unverified, unskipped frame (one in ``--step``) of each
record in ``--records`` it runs the segmenter at the decode thresholds
`segeval` chose for the run, pairs each tracked window with the found quad of
highest IoU, and scores the frame by its worst window. The output is
``<run>/disagreements.json``: per record, the frames sorted worst first, with
each window's IoU and whether the model found a row the tracker has none for.

``--heldout2`` scores the run (and ``--compare``) on the heldout2 stills whose
names match ``--match`` with `rotgate`, once, for the round's report - never
used to choose anything.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image, ImageOps

from pump_reader import rotgate, segnet
from pump_reader.detdata import FRAMES, ROOT, _image_path, rotate_quad
from pump_reader.segtrain import letterbox

sys.path.insert(0, str(ROOT / "scripts"))
import corpus_db  # noqa: E402

DARK = r"black|tft|alexela|night|dark"


def load(run: Path, device: torch.device):
    ck = torch.load(run / "segnet.pt", map_location="cpu")
    model = segnet.SegNet(ck["width"])
    model.load_state_dict(ck["state_dict"])
    model.to(device).eval()
    decode = json.loads((run / "heldout-quads.json").read_text())
    return model, decode


def find(model, decode, img: np.ndarray, device) -> list[list[tuple[float, float]]]:
    """Found quads in the image's pixels, at the run's chosen thresholds."""
    x, s = letterbox(img)
    t = torch.from_numpy(x.transpose(2, 0, 1) / 255.0).float().unsqueeze(0).to(device)
    with torch.no_grad():
        p = torch.sigmoid(model(t))[0].cpu().numpy()
    quads = segnet.decode(p[0], p[1:], decode["pixel_t"], decode["link_t"],
                          decode["min_short"], decode["min_area"], "rect")
    return [[(float(qx) * 2 / s, float(qy) * 2 / s) for qx, qy in q] for q, _ in quads]


def heldout2(runs: list[Path], match: str, device) -> None:
    con = corpus_db.connect(None)
    rows = con.execute(
        "select e.fixture, e.rotationCW, f.path from entries e join fixtures f on f.name = e.fixture "
        "where f.kind = 'pump' and f.split = 'heldout2' "
        "and exists(select 1 from windows w where w.fixture = e.fixture)").fetchall()
    rows = [r for r in rows if re.search(match, r["fixture"])]
    images = {}
    for r in rows:
        rotation = r["rotationCW"] or 0
        im = ImageOps.exif_transpose(Image.open(_image_path(r["path"]))).convert("RGB")
        if rotation:
            im = im.rotate(-rotation, expand=True)
        w, h = im.size
        quads = [rotate_quad(json.loads(q["quad"]), rotation) for q in con.execute(
            "select quad from windows where fixture = ? order by ord", (r["fixture"],))]
        images[r["fixture"]] = (np.array(im), [[(x * w, y * h) for x, y in q] for q in quads])
    con.close()
    print(f"heldout2 stills matching {match!r}: {len(images)}")
    for run in runs:
        model, decode = load(run, device)
        truth = {n: q for n, (_, q) in images.items()}
        found = {n: find(model, decode, img, device) for n, (img, _) in images.items()}
        sc = rotgate.score(truth, found)
        print(sc.line(f"HELDOUT2 {run.name}"))
        for line in sc.per_photo:
            print("  " + line)


def disagreements(run: Path, records: list[str], step: int, device) -> dict:
    model, decode = load(run, device)
    con = corpus_db.connect(None)
    out = {}
    try:
        for record in records:
            t = corpus_db.tracked(record, con=con)
            frames = sorted((n for n, f in t["frames"].items()
                             if f.get("windows") and not f.get("verified") and not f.get("skipped")),
                            key=lambda n: int(n[:-4]))[::step]
            scored = []
            for name in frames:
                path = FRAMES / record / name
                if not path.exists():
                    continue
                img = cv2.cvtColor(cv2.imread(str(path)), cv2.COLOR_BGR2RGB)
                h, w = img.shape[:2]
                found = find(model, decode, img, device)
                windows = []
                for wd in t["frames"][name]["windows"]:
                    q = [(x * w, y * h) for x, y in wd["quad"]]
                    best = max((rotgate.iou(q, f) for f in found), default=0.0)
                    windows.append({"field": wd.get("field"), "iou": round(best, 3)})
                tracked_polys = [[(x * w, y * h) for x, y in wd["quad"]] for wd in t["frames"][name]["windows"]]
                extra = sum(1 for f in found if max((rotgate.iou(f, q) for q in tracked_polys), default=0) < 0.3)
                worst = min((wd["iou"] for wd in windows), default=0.0)
                scored.append({"frame": name, "worst": worst, "extraRows": extra, "windows": windows})
            scored.sort(key=lambda s: (s["worst"], -s["extraRows"]))
            agree = sum(1 for s in scored if s["worst"] >= 0.7 and s["extraRows"] == 0)
            out[record] = {"frames": len(scored), "agree": agree, "worstFirst": scored}
            print(f"{record}: {len(scored)} frames scored, {agree} agree (every window IoU >= 0.7, no extra row), "
                  f"{sum(1 for s in scored if s['worst'] < 0.5)} under 0.5")
    finally:
        con.close()
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pump_reader.segdisagree")
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--compare", type=Path, default=None)
    p.add_argument("--records", nargs="*", default=None,
                   help="records to score; default: every tracked record whose name looks dark")
    p.add_argument("--step", type=int, default=3)
    p.add_argument("--heldout2", action="store_true")
    p.add_argument("--match", default=DARK)
    args = p.parse_args(argv)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    if args.heldout2:
        heldout2([r for r in (args.compare, args.run) if r], args.match, device)
        return 0
    records = args.records
    if records is None:
        con = corpus_db.connect(None)
        stills = {r["record"]: r["still"] for r in con.execute(
            "select record, still from frames where frame = '' and still is not null")}
        records = [r for r in corpus_db.tracked_records(con)
                   if re.search(args.match, r) or re.search(args.match, stills.get(r) or "")]
        con.close()
    result = disagreements(args.run, records, args.step, device)
    (args.run / "disagreements.json").write_text(json.dumps(result, indent=1))
    print(f"wrote {args.run / 'disagreements.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
