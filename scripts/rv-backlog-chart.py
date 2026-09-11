#!/usr/bin/env python3
"""Chart the RV backlog: rows filed against rows closed, commit by commit.

Reads the state of every RV row from `docs/TASKS.md` and `docs/TASKS-DONE.md`
as they stood at each commit that touched either file, so the series is
recomputed from history rather than from a running tally that could drift.

    python3 scripts/rv-backlog-chart.py [--out design/analysis]
"""
import argparse, collections, datetime, json, re, statistics, subprocess, sys
from pathlib import Path

# A row's id may carry a version marker before the cell ends: `RV.118 **[v1.1]**`.
ROW = re.compile(r"^\|\s*\*\*\[(x|~|!|cut| )\]\*\*\s*(RV\.[0-9]+[a-z]?)\b[^|]*\|(.*)$", re.M)
FILES = ("docs/TASKS.md", "docs/TASKS-DONE.md")
DATEFMT = "%Y-%m-%d %H:%M"

# Process changes, dated by the commit that recorded each one. Drawn on the
# chart because the question it answers is what the backlog did around them.
MILESTONES = [
    ("2026-09-08", "backlog split + generated index"),
    ("2026-09-09", "defect patterns; journeys walk made recurring"),
    ("2026-09-10", "scenario rule; six source-scan guards"),
]


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def scan():
    """(series, birth, death, birthtext) with one series point per commit."""
    log = sh("git", "log", "--reverse", "--format=%H|%ad|%s",
             f"--date=format:{DATEFMT}", "--", *FILES).strip().split("\n")
    seen, closed = set(), set()
    birth, death, birthtext, series = {}, {}, {}, []
    for line in log:
        h, date, subj = line.split("|", 2)
        text = "".join(sh("git", "show", f"{h}:{p}") for p in FILES)
        states, texts = {}, {}
        for m in ROW.finditer(text):
            mark, tid, rest = m.groups()
            if states.get(tid) in ("x", "cut"):
                continue  # a closed row wins over its index entry
            states[tid], texts[tid] = mark, rest
        ids = set(states)
        for t in ids - seen:
            birth[t] = {"date": date, "h": h[:7], "subj": subj}
            birthtext[t] = texts[t]
        seen |= ids
        # A row is closed when it is ticked, or when it leaves the files entirely.
        now = {t for t, v in states.items() if v in ("x", "cut")} | (seen - ids)
        for t in now - closed:
            death[t] = {"date": date, "h": h[:7], "subj": subj,
                        "how": "ticked" if t in states else "removed"}
        closed |= now
        series.append({"h": h[:7], "date": date, "subj": subj,
                       "filed": len(seen), "closed": len(closed),
                       "open": len(seen) - len(closed)})
    return series, birth, death, birthtext


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="design/analysis")
    args = ap.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)

    series, birth, death, birthtext = scan()
    series = [c for c in series if c["filed"] > 0]
    if not series:
        sys.exit("no RV rows found")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates

    when = [datetime.datetime.strptime(c["date"], DATEFMT) for c in series]
    filed = [c["filed"] for c in series]
    done = [c["closed"] for c in series]
    openn = [c["open"] for c in series]

    per_day = lambda d: collections.Counter(v["date"][:10] for v in d.values())
    b, k = per_day(birth), per_day(death)
    days = sorted(set(b) | set(k))
    dts = [datetime.datetime.strptime(d, "%Y-%m-%d") for d in days]

    lead = collections.defaultdict(list)
    for t, dd in death.items():
        hrs = (datetime.datetime.strptime(dd["date"], DATEFMT)
               - datetime.datetime.strptime(birth[t]["date"], DATEFMT)).total_seconds() / 3600
        lead[dd["date"][:10]].append(hrs)

    INK, TAIL, HEAD, AMBER = "#E8EAED", "#FF5C3D", "#4FA8FF", "#FFB020"
    plt.rcParams.update({
        "figure.facecolor": "#14161A", "axes.facecolor": "#14161A",
        "axes.edgecolor": "#2A2E35", "axes.labelcolor": INK,
        "text.color": INK, "xtick.color": "#9AA0A6", "ytick.color": "#9AA0A6",
        "grid.color": "#24282F", "font.size": 10,
    })

    fig, (ax, ax2, ax3) = plt.subplots(
        3, 1, figsize=(13, 12), height_ratios=[3, 1.5, 1.3], sharex=True)

    # 1. cumulative filed against closed
    ax.plot(when, filed, color=TAIL, lw=2.2, label=f"filed (cumulative) - {filed[-1]}")
    ax.plot(when, done, color=HEAD, lw=2.2, label=f"closed (cumulative) - {done[-1]}")
    ax.fill_between(when, done, filed, color=AMBER, alpha=0.13,
                    label=f"open backlog - {openn[-1]} now")
    ax.set_ylabel("RV rows")
    ax.set_title("The RV backlog, commit by commit", loc="left", fontsize=15, pad=14)
    ax.legend(loc="upper left", facecolor="#1A1D22", edgecolor="#2A2E35", framealpha=1)
    ax.grid(True, alpha=0.5, lw=0.6)
    # The process changes, each dated from the commit that recorded it. They are
    # the point of the chart: what the backlog did on either side of them.
    for day, label in MILESTONES:
        x = datetime.datetime.strptime(day, "%Y-%m-%d")
        if not (when[0] <= x <= when[-1]):
            continue
        for a in (ax, ax2, ax3):
            a.axvline(x, color="#5A6472", lw=1, ls=":", zorder=0)
        ax.text(x + datetime.timedelta(hours=2), ax.get_ylim()[1] * 0.055, label,
                color="#9AA0A6", fontsize=8.5, rotation=90, va="bottom")

    # 2. filed and closed per day
    w = 0.36
    ax2.bar([d - datetime.timedelta(hours=5) for d in dts], [b[d] for d in days],
            width=w, color=TAIL, label="filed that day")
    ax2.bar([d + datetime.timedelta(hours=5) for d in dts], [k[d] for d in days],
            width=w, color=HEAD, label="closed that day")
    ax2.set_ylabel("rows / day")
    ax2.legend(loc="upper left", facecolor="#1A1D22", edgecolor="#2A2E35", framealpha=1)
    ax2.grid(True, axis="y", alpha=0.5, lw=0.6)

    # 3. how long a row waited
    med = [statistics.median(lead[d]) if lead.get(d) else 0 for d in days]
    ax3.bar(dts, med, width=0.6, color="#7C8592")
    overall = statistics.median([h for v in lead.values() for h in v])
    ax3.axhline(overall, color=AMBER, lw=1.2, ls="--")
    ax3.text(dts[0], overall + 0.4, f"overall median {overall:.1f} h",
             color=AMBER, fontsize=9)
    ax3.set_ylabel("median h\nto close")
    ax3.grid(True, axis="y", alpha=0.5, lw=0.6)
    ax3.xaxis.set_major_formatter(mdates.DateFormatter("%b %-d"))
    ax3.xaxis.set_major_locator(mdates.DayLocator())

    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    fig.text(0.01, 0.012,
             f"Snapshot {stamp} · recomputed from {len(series)} commits to "
             f"{' and '.join(FILES)} · median {overall:.1f} h from filing to ticking",
             color="#6B7280", fontsize=8.5)
    fig.tight_layout(rect=(0, 0.03, 1, 1))

    png = out / "rv-backlog.png"
    fig.savefig(png, dpi=160)
    print(f"{png}  ({len(series)} commits, {filed[-1]} filed, {done[-1]} closed, {openn[-1]} open)")

    json.dump({"series": series, "birth": birth, "death": death},
              open(out / "rv-backlog.json", "w"), indent=1)
    print(out / "rv-backlog.json")


if __name__ == "__main__":
    main()
