"""CLI: ``python -m pump_reader.rowtrain --export <train export dir> --out <run> [--seed 0]``.

Trains the PU.77 row reader (`rowreader.CRNN`) as `agents/research/PU.77.md` §4.5 sets it:
synthetic strips from the renderer (`row.render_row_of_labels` on the 96 px strip canvas) with
strings drawn from the measured display conventions (§4.3), mixed with the re-exported TRAIN strips
at 30 % of every batch, the real pool capped at 2 % per source (Baek §4.2's diversity finding);
AdaDelta rho 0.95 with gradient clipping 5 (Baek §4.1); selection on a fixture-grouped 10 % of the
real train strips and a fixed synthetic set - never on heldout (decision 9).
"""

from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from torch.utils.data import DataLoader, Dataset, IterableDataset

from pump_reader import rowreader as rr
from pump_reader.profiles import PROFILES, sample_make
from pump_reader.row import parse_row, render_row_of_labels

# Read placements by (currency, field) and cell count, as the reviewed corpus shows them
# (`PumpDisplayConventions`, placementsByCells and the field sets); `board` reads as a price.
CONVENTIONS = {
    "EUR": {"liters": {3: [2], 4: [2], 6: [2]}, "total": {4: [2], 5: [2], 6: [2]}, "unitPrice": {4: [3]}},
    "RUB": {"liters": {3: [2], 4: [2], 5: [2], 6: [2], 7: [2]},
            "total": {4: [1], 5: [1, 2], 6: [1, 2], 7: [2]}, "unitPrice": {3: [1], 4: [2], 5: [2]}},
    "KZT": {"liters": {4: [2]}, "total": {4: [0], 5: [0]}, "unitPrice": {3: [0], 4: [1]}},
    "GBP": {"liters": {3: [2], 4: [2]}, "total": {3: [2], 4: [2], 5: [2]}, "unitPrice": {4: [3]}},
}
CURRENCY_MIX = {"EUR": 0.55, "RUB": 0.35, "KZT": 0.05, "GBP": 0.05}
FIELD_MIX = {"total": 0.3, "liters": 0.3, "unitPrice": 0.25, "board": 0.15}


def sample_text(rng: np.random.Generator) -> str:
    cur = rng.choice(list(CURRENCY_MIX), p=list(CURRENCY_MIX.values()))
    field = rng.choice(list(FIELD_MIX), p=list(FIELD_MIX.values()))
    table = CONVENTIONS[cur]["unitPrice" if field == "board" else field]
    cells = int(rng.choice(list(table)))
    d = int(rng.choice(table[cells]))
    digits = [str(v) for v in rng.integers(0, 10, size=cells)]
    # Zero padding (`0032,49`) on some heads; otherwise a leading digit is never zero unless the
    # integer part is a single digit.
    if cells - d > 1 and rng.random() > 0.2:
        digits[0] = str(rng.integers(1, 10))
    if d == 0:
        return "".join(digits)
    return "".join(digits[:cells - d]) + "." + "".join(digits[cells - d:])


def render(text: str, rng: np.random.Generator) -> Image.Image:
    profile = PROFILES[sample_make(rng)]
    cells = parse_row(text, profile.dp_own_cell)
    img, _ = render_row_of_labels(cells, profile, rng, strip_h=96, comma=bool(rng.random() < 0.5))
    return img


class Synthetic(IterableDataset):
    def __init__(self, seed: int):
        self.seed = seed

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        rng = np.random.default_rng(self.seed * 1000 + (info.id if info else 0))
        while True:
            text = sample_text(rng)
            yield rr.to_input(render(text, rng)), rr.encode(text)


class Real(Dataset):
    def __init__(self, items: list[dict]):
        self.items = items

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, i: int):
        it = self.items[i]
        return rr.to_input(Image.open(it["strip"])), it["tokens"]


def cap(items: list[dict], share: float, seed: int) -> list[dict]:
    """Every source group at most `share` of the pool, by uniform subsampling."""
    groups: dict[str, list[dict]] = defaultdict(list)
    for it in items:
        groups[it["group"]].append(it)
    limit = max(1, int(share * len(items)))
    rng = np.random.default_rng(seed)
    out = []
    for g in sorted(groups):
        members = groups[g]
        if len(members) > limit:
            members = [members[i] for i in rng.choice(len(members), limit, replace=False)]
        out += members
    return out


def as_list(samples):
    return samples


def collate(samples):
    arrays, labels = zip(*samples)
    x, lengths = rr.batch(list(arrays))
    targets = torch.tensor([t for lab in labels for t in lab], dtype=torch.long)
    target_lengths = torch.tensor([len(lab) for lab in labels], dtype=torch.long)
    return x, lengths, targets, target_lengths, list(labels)


def evaluate(model, loader, device) -> dict:
    model.eval()
    n = exact = length = sep_ok = 0
    with torch.no_grad():
        for x, lengths, _, _, labels in loader:
            lp = model(x.to(device)).log_softmax(2).cpu().numpy()
            for i, label in enumerate(labels):
                got = rr.best_path(lp[: lengths[i], i])
                n += 1
                exact += got == label
                length += sum(t != rr.SEP for t in got) == sum(t != rr.SEP for t in label)
                sep_ok += [j for j, t in enumerate(got) if t == rr.SEP] == [j for j, t in enumerate(label) if t == rr.SEP]
    model.train()
    return {"n": n, "string": exact / max(n, 1), "length": length / max(n, 1), "sep": sep_ok / max(n, 1)}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pump_reader.rowtrain")
    p.add_argument("--export", type=Path, nargs="+", required=True,
                   help="train export folders; each one's train-slices.json and train-videos.json are read")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--steps", type=int, default=20_000)
    p.add_argument("--batch", type=int, default=64)
    p.add_argument("--real-frac", type=float, default=0.3)
    p.add_argument("--cap", type=float, default=0.02)
    p.add_argument("--workers", type=int, default=5)
    p.add_argument("--max-hours", type=float, default=3.0)
    args = p.parse_args(argv)
    torch.manual_seed(args.seed)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    args.out.mkdir(parents=True, exist_ok=True)

    real = [r for folder in args.export for r in rr.load_real(folder)]
    train_real = cap([r for r in real if not rr.is_val_group(r["group"])], args.cap, args.seed)
    val_real = [r for r in real if rr.is_val_group(r["group"])]
    n_real = int(round(args.batch * args.real_frac))
    real_loader = DataLoader(Real(train_real), batch_size=n_real, shuffle=True, drop_last=True,
                             collate_fn=as_list, num_workers=2, persistent_workers=True)
    synth_loader = DataLoader(Synthetic(args.seed), batch_size=args.batch - n_real,
                              collate_fn=as_list, num_workers=args.workers, persistent_workers=True)
    val_rng = np.random.default_rng(10_000 + args.seed)
    synth_val = [(rr.to_input(render(t, val_rng)), rr.encode(t)) for t in (sample_text(val_rng) for _ in range(500))]
    val_real_loader = DataLoader(Real(val_real), batch_size=64, collate_fn=collate, num_workers=2)
    val_synth_loader = DataLoader(synth_val, batch_size=64, collate_fn=collate)

    model = rr.CRNN().to(device)
    opt = torch.optim.Adadelta(model.parameters(), lr=1.0, rho=0.95)
    ctc = torch.nn.CTCLoss(blank=rr.BLANK, zero_infinity=True)
    log = {"real_pool": len(real), "train_real_capped": len(train_real), "val_real": len(val_real),
           "real_per_batch": n_real, "seed": args.seed, "evals": []}
    print(json.dumps({k: v for k, v in log.items() if k != "evals"}), flush=True)
    best, step, t0, running = -1.0, 0, time.time(), []
    real_iter, synth_iter = iter(real_loader), iter(synth_loader)
    while step < args.steps:
        try:
            r = next(real_iter)
        except StopIteration:
            real_iter = iter(real_loader)
            r = next(real_iter)
        x, lengths, targets, target_lengths, _ = collate(list(r) + next(synth_iter))
        logits = model(x.to(device))
        lp = logits.log_softmax(2).float().cpu()  # CTC on the CPU: the MPS kernel is not available
        loss = ctc(lp, targets, lengths, target_lengths)
        opt.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
        opt.step()
        running.append(float(loss.detach()))
        step += 1
        if step % 200 == 0:
            print(f"step {step} loss {np.mean(running):.4f} {time.time() - t0:.0f}s", flush=True)
            running = []
        if step % 2000 == 0 or step == args.steps:
            vr, vs = evaluate(model, val_real_loader, device), evaluate(model, val_synth_loader, device)
            log["evals"].append({"step": step, "val_real": vr, "val_synth": vs})
            print(f"  eval {step}: real {vr} synth {vs}", flush=True)
            if vr["string"] > best:
                best = vr["string"]
                torch.save({"state_dict": model.state_dict(), "step": step}, args.out / "crnn.pt")
            (args.out / "metrics.json").write_text(json.dumps(log, indent=1))
        if time.time() - t0 > args.max_hours * 3600:
            print(f"stopped at the {args.max_hours} h budget, step {step}", flush=True)
            log["stopped_at_budget"] = step
            break
    log["best_val_real_string"] = best
    log["wall_seconds"] = round(time.time() - t0)
    (args.out / "metrics.json").write_text(json.dumps(log, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
