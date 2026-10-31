"""PLAN.md §4 D318 — `start_anchor` is what a user typed, not an engine input.

A disruption whose start was entered as an ISO week or a date carries
`start_anchor` beside `start_day`. The mapper reads `start_day` and nothing else
about timing, so the same schedule with and without the anchor maps to the same
events and the same warnings. This test lives outside `scsim/scsim/`, so it
changes no engine build (gate `engine-ledger`).
"""
from scsim.io.project_map import _map_events


def _schedule(with_anchor: bool) -> list[dict]:
    events = [
        {"target": "supplier:S1", "target_type": "node", "start_day": 175, "duration_days": 28,
         "magnitude_pct": 100},
        {"target": "node:plant", "target_type": "node", "start_day": 140, "duration_days": 14,
         "magnitude_pct": 40},
    ]
    if with_anchor:
        events[0]["start_anchor"] = {"kind": "iso_week", "value": "2027-W26", "project_start": "2027-01-04"}
        # An anchor that disagrees with start_day: the engine still runs start_day.
        events[1]["start_anchor"] = {"kind": "date", "value": "2030-01-01", "project_start": "2027-01-04"}
    return events


def test_the_anchor_changes_no_event_and_no_warning():
    plain_w: list = []
    anch_w: list = []
    plain = _map_events(_schedule(False), {"S1"}, {"S1": None}, plain_w)
    anchored = _map_events(_schedule(True), {"S1"}, {"S1": None}, anch_w)
    assert [e.model_dump() for e in anchored] == [e.model_dump() for e in plain]
    assert [str(x) for x in anch_w] == [str(x) for x in plain_w]
    assert [e.start for e in anchored] == [25, 20]
