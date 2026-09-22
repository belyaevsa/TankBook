"""The resident video-frame reader behind the annotator's re-read after a retrack.

`pump-read --read-serve` loads the classifier once and reads one frame per stdin
line through `PumpVideoFrameRead` - the code `PumpVideoReadTests` labels with -
so a re-read of the frames a Save moved costs the reads, not a `swift test`
launch (about a minute before the first frame). `read_video` mirrors that
test's `label()` for one record: the same frame selection, the same skip set
(owner labels, interpolations between owner keyframes, skipped frames,
verified frames), the same staging file through `corpus_db.import_readings`.
The test stays the batch and CI path; this is the interactive one.
"""
from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "scripts"))
import corpus_db  # noqa: E402


class ResidentReader:
    def __init__(self, binary: Path, build: "callable[[], bool] | None" = None, cwd: Path | None = None):
        self.binary = binary
        self.build = build
        self.cwd = cwd
        self.proc: subprocess.Popen | None = None
        self.lock = threading.Lock()
        self.last_error: str | None = None

    def _ensure(self) -> bool:
        if self.proc and self.proc.poll() is None:
            return True
        if not self.binary.exists() and self.build and not self.build():
            self.last_error = "pump-read did not build"
            return False
        try:
            self.proc = subprocess.Popen([str(self.binary), "--read-serve"], cwd=self.cwd,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                         text=True, bufsize=1)
        except OSError as exc:
            self.last_error = str(exc)
            return False
        return True

    def read(self, request: dict) -> dict:
        """One frame. Requests are serialised: a retrack's batch holds the
        process for one frame at a time, never interleaved with another's."""
        with self.lock:
            if not self._ensure():
                return {"error": self.last_error or "reader unavailable"}
            assert self.proc and self.proc.stdin and self.proc.stdout
            try:
                self.proc.stdin.write(json.dumps(request) + "\n")
                self.proc.stdin.flush()
                line = self.proc.stdout.readline()
            except (BrokenPipeError, OSError) as exc:
                self.proc = None
                return {"error": f"reader died: {exc}"}
            if not line:
                self.proc = None
                return {"error": "reader exited"}
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                return {"error": "reader replied with something that is not JSON"}

    def stop(self) -> None:
        with self.lock:
            if self.proc and self.proc.poll() is None:
                try:
                    self.proc.stdin.close()
                    self.proc.wait(timeout=2)
                except Exception:
                    self.proc.kill()
            self.proc = None


def _number(frame: str) -> int:
    try:
        return int(frame[:-4])
    except ValueError:
        return 0


def human_skipped(names: list[str], labels: dict) -> set[str]:
    """PumpVideoReadTests.humanSkipped: every owner label, and an interpolated
    label whose nearest keyframes on both sides are still owner."""
    source = lambda n: (labels.get(n) or {}).get("source")
    skip = set()
    for i, name in enumerate(names):
        s = source(name)
        if s == "owner":
            skip.add(name)
        elif s == "interpolated" and any(source(n) == "owner" for n in names[:i]) \
                and any(source(n) == "owner" for n in names[i + 1:]):
            skip.add(name)
    return skip


def read_video(reader: ResidentReader, stem: str, start: str | None = None, frames: list[str] | None = None,
               progress: "callable[[int, int], None] | None" = None) -> str:
    """Read one video's frames in scope and import them; returns a summary line
    in the test's shape. `start` / `frames` scope the read exactly as
    PUMP_VIDEO_READ_FROM / PUMP_VIDEO_READ_FRAMES do."""
    videos = json.loads(corpus_db.VIDEOS_FILE.read_text())
    video = videos.get(stem)
    if not isinstance(video, dict) or video.get("reviewed"):
        return f"{stem}: not read (reviewed or unknown)"
    price_text = video.get("unitPrice")
    try:
        float(str(price_text).replace(",", "."))
    except ValueError:
        return f"{stem}: not read (no unit price)"
    tracked_file = corpus_db.FRAMES / stem / "windows.json"
    try:
        tracked = json.loads(tracked_file.read_text()).get("frames") or {}
    except (OSError, json.JSONDecodeError):
        return f"{stem}: not read (no tracked frames)"
    listed = set(frames) if frames is not None else None
    names = sorted(tracked, key=_number)
    names = [n for n in names if (start is None or _number(n) >= _number(start)) and (listed is None or n in listed)]
    labels_all = json.loads(corpus_db.LABELS_FILE.read_text()) if corpus_db.LABELS_FILE.exists() else {}
    existing = labels_all.get(stem) or {}
    skip = human_skipped(names, existing) | {n for n in names if (tracked.get(n) or {}).get("skipped")}
    readings, arithmetic, read, closed = {}, {}, 0, 0
    todo = [n for n in names if n not in skip and not (tracked.get(n) or {}).get("verified")
            and (tracked.get(n) or {}).get("windows") is not None]
    started = time.time()
    for i, name in enumerate(todo):
        if progress:
            progress(i, len(todo))
        image = corpus_db.LIVE / "frames" / stem / name
        if not image.exists():
            continue
        windows = [{"field": w["field"], "quad": w["quad"]} for w in tracked[name]["windows"]
                   if isinstance(w, dict) and "field" in w and "quad" in w]
        reply = reader.read({"image": str(image), "priceText": price_text, "windows": windows})
        if reply.get("error"):
            raise RuntimeError(reply["error"])
        if not reply.get("reading"):
            continue
        read += 1
        readings[name] = reply["reading"]
        if reply.get("label"):
            closed += 1
            arithmetic[name] = reply["label"]
    staged = {"record": stem, "readings": readings, "labels": arithmetic}
    if start:
        staged["from"] = start
    if frames is not None:
        staged["frames"] = sorted(frames)
    staging = HERE.parents[1] / "ml" / "pump-reader" / ".out" / "video-read" / f"{stem}.resident.json"
    staging.parent.mkdir(parents=True, exist_ok=True)
    staging.write_text(json.dumps(staged, sort_keys=True))
    corpus_db.import_readings(staging)
    labelled = set(existing) | set(arithmetic)
    return (f"{stem[:9]}: {closed} of {read} frames closed ({len(labelled)} labelled)"
            f" · {int((time.time() - started) * 1000)} ms")
