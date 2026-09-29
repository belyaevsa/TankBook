"""Tests for scripts/pump-live-diff.py (PU.56)."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location("pump_live_diff", Path(__file__).with_name("pump-live-diff.py"))
pld = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pld)


def field(outcome: str, got: float | None = None, want: float = 10.0, reason: str | None = None) -> dict:
    return {"outcome": outcome, "got": got, "want": want, "reason": reason}


def ledger(fields_by_still: dict[str, dict[str, dict]]) -> dict:
    return {"totals": {}, "stills": [{"name": n, "head": "wayne", "fields": f} for n, f in fields_by_still.items()]}


def test_flips_are_named_by_the_stage_they_moved_at() -> None:
    before = ledger({
        "pump-001.jpg": {"total": field("right", 10.0)},
        "pump-002.jpg": {"total": field("right", 10.0)},
        "pump-003.jpg": {"total": field("right", 10.0)},
    })
    after = ledger({
        "pump-001.jpg": {"total": field("abstained", reason="boardFoundNoPrice")},
        "pump-002.jpg": {"total": field("abstained", reason="cellUnknown")},
        "pump-003.jpg": {"total": field("wrong", 100.0)},
    })
    kinds = {r["still"]: r["kind"] for r in pld.diff(before, after)}
    assert kinds == {"pump-001.jpg": "law flip", "pump-002.jpg": "read flip", "pump-003.jpg": "WRONG"}


def test_an_unchanged_pair_diffs_to_nothing() -> None:
    same = ledger({"pump-001.jpg": {"total": field("right", 10.0), "liters": field("abstained", reason="nothingClosed")}})
    assert pld.diff(same, same) == []


def test_gains_moved_reasons_and_unscored_fields() -> None:
    before = ledger({
        "pump-001.jpg": {"liters": field("abstained", reason="nothingClosed"), "unitPrice": field("unscored")},
        "pump-002.jpg": {"liters": field("abstained", reason="nothingClosed")},
    })
    after = ledger({
        "pump-001.jpg": {"liters": field("right", 10.0), "unitPrice": field("right", 1.0)},
        "pump-002.jpg": {"liters": field("abstained", reason="cellUnknown")},
    })
    kinds = sorted((r["still"], r["field"], r["kind"]) for r in pld.diff(before, after))
    assert kinds == [("pump-001.jpg", "liters", "gain"), ("pump-002.jpg", "liters", "reason")]


def test_a_still_present_in_one_ledger_only() -> None:
    before = ledger({})
    after = ledger({"pump-009.jpg": {"total": field("wrong", 5.0)}})
    assert [r["kind"] for r in pld.diff(before, after)] == []
    assert "changed fields: none" in pld.report(before, after)


def test_a_whole_photo_refusal_names_the_stage_through_the_photos_reason() -> None:
    before = ledger({"pump-001.jpg": {"total": field("right", 10.0)}})
    after = {"totals": {}, "stills": [{"name": "pump-001.jpg", "head": "wayne", "reason": "noTotalWindow",
                                       "fields": {"total": field("abstained")}}]}
    rows = pld.diff(before, after)
    assert [(r["kind"], r["after"]) for r in rows] == [("assign flip", "noTotalWindow")]


def test_a_display_refusal_is_a_locate_flip() -> None:
    before = ledger({"pump-001.jpg": {"total": field("right", 10.0)}})
    after = {"totals": {}, "stills": [{"name": "pump-001.jpg", "head": "tokheim", "reason": "notADisplay",
                                       "fields": {"total": field("abstained")}}]}
    assert [r["kind"] for r in pld.diff(before, after)] == ["locate flip"]
