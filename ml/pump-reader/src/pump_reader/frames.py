"""CLI: ``python -m pump_reader.frames [--only live-6229] [--force]``.

Extracts every frame of every movie in ``fixtures/pump-live/`` (the Live
Photo records and the plain videos, pulled from the bucket by
``scripts/corpus-sync.py``) into ``pump-live/frames/<stem>/NNN.jpg`` - the
``ffmpeg`` line the pump-live README documents, run for the whole folder.
``frames/`` is gitignored and regenerates from the movies; a folder that
already holds the movie's frame count is skipped unless ``--force``.

Frames are the raw material of ``pump_reader.track`` (the still's quads
carried through the record) and of the running-display measurements; this
step neither reads nor labels anything.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
LIVE = ROOT / "Spike" / "ReceiptSpike" / "fixtures" / "pump-live"
FRAMES = LIVE / "frames"
MOVIE_SUFFIXES = (".mov", ".mp4", ".MOV", ".MP4")


def probe(movie: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
         "-show_entries", "stream=width,height,nb_read_frames,r_frame_rate", "-of", "json", str(movie)],
        capture_output=True, text=True, check=True).stdout
    streams = json.loads(out).get("streams") or []
    if not streams or "nb_read_frames" not in streams[0]:
        # A record with no decodable video stream (live-5916 - a zero-frame
        # capture the camera roll still exported): nothing to extract.
        return {"width": 0, "height": 0, "frames": 0, "fps": 0.0}
    stream = streams[0]
    num, den = stream["r_frame_rate"].split("/")
    return {"width": int(stream["width"]), "height": int(stream["height"]),
            "frames": int(stream["nb_read_frames"]), "fps": int(num) / int(den)}


def first_frame(stem: str) -> int:
    """The first usable frame of a video (`firstFrame` in videos.json, e.g.
    "047.jpg"): a clip whose opening frames are corrupt or show no display
    drops them at extraction, so nothing downstream ever sees them."""
    videos = LIVE / "videos.json"
    if not videos.exists():
        return 1
    entry = json.loads(videos.read_text()).get(stem, {})
    name = entry.get("firstFrame") if isinstance(entry, dict) else None
    return int(name[:-4]) if name else 1


def extract(movie: Path, force: bool = False) -> tuple[Path, int, bool]:
    """Returns (folder, frame count, extracted-now)."""
    folder = FRAMES / movie.stem
    info = probe(movie)
    start = first_frame(movie.stem)
    have = len(list(folder.glob("*.jpg"))) if folder.exists() else 0
    if info["frames"] == 0 or (have == info["frames"] - (start - 1) and not force):
        return folder, have, False
    if folder.exists():
        for old in folder.glob("*.jpg"):
            old.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(movie), "-fps_mode", "passthrough", "-q:v", "2",
         str(folder / "%03d.jpg")],
        check=True)
    for early in folder.glob("*.jpg"):
        if early.stem.isdigit() and int(early.stem) < start:
            early.unlink()
    (folder / "movie.json").write_text(json.dumps({"movie": movie.name, "firstFrame": start, **info}, indent=1))
    return folder, len(list(folder.glob("*.jpg"))), True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pump_reader.frames")
    parser.add_argument("--only", action="append", default=[], help="movie stem(s) to extract")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    movies = sorted(p for p in LIVE.iterdir() if p.suffix in MOVIE_SUFFIXES)
    if args.only:
        movies = [m for m in movies if m.stem in args.only]
    if not movies:
        print(f"no movies under {LIVE} - scripts/corpus-sync.py pull first")
        return 1
    total = 0
    for movie in movies:
        folder, count, fresh = extract(movie, args.force)
        total += count
        print(f"{movie.stem}: {count} frames{' (extracted)' if fresh else ''}")
    print(f"{len(movies)} movies, {total} frames under {FRAMES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
