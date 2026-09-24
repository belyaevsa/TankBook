"""CLI: ``python -m pump_reader.roweval --run <run> --heldout <dir> --export <train export dir>``.

Scores the PU.77 row reader against `agents/research/PU.77.md` §6.2 on the heldout strips the Swift
harness wrote (`PumpRowReaderSpikeTests`, `PUMP_ROWREADER=export`) - the same pixels the current
reader read, whose strings sit beside them:

* B1 on the transaction strips: exact string (digits, count, separator placement), normalised
  Levenshtein digit accuracy (a wrong-count read scored, not voided), per-glyph digit accuracy on
  the count-matched subset; for the row reader (prefix search and the best-path control) and for
  the current arm.
* One shared temperature T fitted by CTC negative log-likelihood on the train-side validation
  strips (Guo et al.'s scaling, `temperature.fit_temperature`'s golden-section pattern), then the
  per-position posteriors written raw and T-scaled for the law harness.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch
from PIL import Image

from pump_reader import rowreader as rr

TRANSACTION = {"total", "liters", "unitPrice"}


def log_probs(model, strips: list[Image.Image], device) -> list[np.ndarray]:
    out = []
    with torch.no_grad():
        for img in strips:
            a = rr.to_input(img)
            x, lengths = rr.batch([a])
            z = model(x.to(device))[:, 0].float().cpu()
            out.append((z, int(lengths[0])))
    return out


def fit_temperature(logits: list[tuple[torch.Tensor, int]], labels: list[list[int]]) -> float:
    ctc = torch.nn.CTCLoss(blank=rr.BLANK, reduction="sum", zero_infinity=True)

    def nll(t: float) -> float:
        total = 0.0
        for (z, n), lab in zip(logits, labels):
            lp = (z[:n] / t).log_softmax(1).unsqueeze(1)
            total += float(ctc(lp, torch.tensor([lab]), torch.tensor([n]), torch.tensor([len(lab)])))
        return total

    lo, hi = math.log(0.25), math.log(4.0)
    g = (math.sqrt(5) - 1) / 2
    a, b = hi - g * (hi - lo), lo + g * (hi - lo)
    fa, fb = nll(math.exp(a)), nll(math.exp(b))
    for _ in range(30):
        if fa < fb:
            hi, b, fb = b, a, fa
            a = hi - g * (hi - lo)
            fa = nll(math.exp(a))
        else:
            lo, a, fa = a, b, fb
            b = lo + g * (hi - lo)
            fb = nll(math.exp(b))
    return math.exp((lo + hi) / 2)


def digits_of(tokens: list[int]) -> str:
    return "".join(str(t - 1) for t in tokens if t != rr.SEP)


def b1(pairs: list[tuple[list[int] | None, list[int]]]) -> dict:
    n = len(pairs)
    exact = lev = glyph_ok = glyph_n = 0
    for got, truth in pairs:
        got = got or []
        exact += got == truth
        td, gd = digits_of(truth), digits_of(got)
        lev += max(0.0, 1 - rr.levenshtein(gd, td) / max(len(td), 1))
        if len(gd) == len(td):
            glyph_n += len(td)
            glyph_ok += sum(a == b for a, b in zip(gd, td))
    return {"windows": n, "exact": round(exact / n, 4), "levenshtein": round(lev / n, 4),
            "glyph_count_matched": round(glyph_ok / max(glyph_n, 1), 4), "glyphs": glyph_n}


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (round(c - h, 4), round(c + h, 4))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pump_reader.roweval")
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--heldout", type=Path, required=True)
    p.add_argument("--export", type=Path, nargs="+", required=True)
    p.add_argument("--tag", default="heldout", help="output name prefix (heldout2 for the second frozen draw)")
    args = p.parse_args(argv)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model = rr.CRNN()
    model.load_state_dict(torch.load(args.run / "crnn.pt", map_location="cpu")["state_dict"])
    model.to(device).eval()

    # T on the train-side validation strips (never heldout).
    val = [r for folder in args.export for r in rr.load_real(folder) if rr.is_val_group(r["group"])]
    val_logits = log_probs(model, [Image.open(r["strip"]) for r in val], device)
    temperature = fit_temperature(val_logits, [r["tokens"] for r in val])

    index = json.loads((args.heldout / "index.json").read_text())
    strips = [Image.open(args.heldout / e["strip"]) for e in index]
    logits = log_probs(model, strips, device)
    report: dict = {"temperature": round(temperature, 4), "val_strips": len(val)}
    arms: dict[str, list] = {"prefix": [], "best_path": [], "current": []}
    posts = {"raw": [], "scaled": []}
    for e, (z, n) in zip(index, logits):
        truth = rr.encode(e["text"])
        lp_raw = z[:n].log_softmax(1).numpy()
        pre = rr.prefix_search(lp_raw)
        if e["field"] in TRANSACTION and truth is not None:
            arms["prefix"].append((pre, truth))
            arms["best_path"].append((rr.best_path(lp_raw), truth))
            arms["current"].append((rr.encode(e["current"]) if e.get("current") else None, truth))
        for key, t in (("raw", 1.0), ("scaled", temperature)):
            lp = (z[:n] / t).log_softmax(1).numpy()
            tokens = rr.prefix_search(lp)
            po = rr.posteriors(lp, tokens)
            posts[key].append({"fixture": e["fixture"], "window": e["window"], "field": e["field"],
                               "positions": [[{"digit": d, "logp": lp_} for d, lp_ in r] for r in po.ranked],
                               "sep": po.sep, "decoded": rr.decode_tokens(tokens)})
    for arm, pairs in arms.items():
        s = b1(pairs)
        k = round(s["exact"] * s["windows"])
        s["exact_wilson95"] = wilson(k, s["windows"])
        report[arm] = s
    sep_pairs = arms["prefix"]
    report["sep_placement"] = round(sum([i for i, t in enumerate(g) if t == rr.SEP] ==
                                        [i for i, t in enumerate(tr) if t == rr.SEP] for g, tr in sep_pairs)
                                    / max(len(sep_pairs), 1), 4)
    report["length"] = round(sum(len(digits_of(g)) == len(digits_of(tr)) for g, tr in sep_pairs)
                             / max(len(sep_pairs), 1), 4)
    for key in posts:
        (args.run / (f"posteriors-{key}.json" if args.tag == "heldout" else f"{args.tag}-posteriors-{key}.json")).write_text(json.dumps(posts[key]))
    (args.run / f"{args.tag}-b1.json").write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
