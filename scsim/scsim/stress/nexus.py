# SCSIM — supply chain simulation library and stress-test framework.
# Copyright (c) 2023-2026 Phu Nguyen. All rights reserved until the open-access
# release; see scsim/NOTICE.md for licensing, funding and citation.
# Developed in part within the ACCURATE project (Horizon Europe, GA 101138269).

"""The nexus battery — PLAN.md §27 WP 17.2 (§4 D310).

Every SUPPLIER and every supplied MATERIAL of a scenario is disrupted ALONE
under one shared scenario, and the battery records the sales each outage
costs. Nexus is the resulting table, ranked by the average over the eight
durations. The scenario is ``NEXUS_SCENARIO``, authored here once (§27.2
rule 1) and exported to the registry for every other reader.

* **Targets** (rule 2): suppliers, and materials — every engine material has a
  qualified supplier, and a sub-assembly is a product, so neither products,
  sub-assemblies, customers nor the plant can be named.
* **The event** (rule 2): a full outage (lead-time extension) starting in
  absolute week ``max(26, t_w + 1)``, where ``t_w`` is the warm-up the clean
  reference adopts — shared by every cell — for each duration 2…9 weeks.
* **Policies** (rule 3): the scenario's own, unchanged.
* **The measure** (rule 4): Δ lost sales in € (``lost_sales_value``) over the
  KPI window, cell − clean reference, PAIRED per model replication (common
  random numbers: every cell restores the clean run's warm snapshots).
* **The order** (rule 5): Average desc, then the 9-week cell desc, then the
  target kind and id — never arbitrary.

Sharding: a battery over a subset of targets (``targets=``) gives exactly the
rows the full battery gives for them, because every cell depends only on the
clean reference; ``expected_warmup`` / ``expected_clean_digest`` make a shard
refuse to run against a different reference than the one it was handed.
"""
from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass, field
from typing import Iterable, Optional

import numpy as np

from scsim.core.engine import compile_scenario, resolve_warmup, run_scenario
from scsim.entities.disruption import DisruptionEvent
from scsim.entities.enums import EffectType, ReplicationStopping, TargetType
from scsim.entities.scenario import Scenario
from scsim.stats.bootstrap import aggregate_mean_ci

#: The ONE statement of the shared scenario (§27.2 rule 1). Bump `version`
#: when any field changes: it is part of every stored battery's key.
NEXUS_SCENARIO: dict = {
    "version": 1,
    "start_week": 26,
    "start_rule": "max(start_week, warmup_end + 1)",
    "durations_weeks": [2, 3, 4, 5, 6, 7, 8, 9],
    "effect": EffectType.LEAD_TIME_EXTENSION.value,
    "target_kinds": ["supplier", "material"],
    "measure": "lost_sales_value",
    "measure_unit": "EUR",
    "baseline": "the same scenario with no event, paired per model replication",
    "rank_by": "average",
    "tie_break": ["duration_9", "target_kind", "target_id"],
}

#: Below this a Δ is a zero (float noise, not a loss).
ZERO_EUR = 1e-6


class NexusBatteryError(ValueError):
    """The battery cannot be run as declared — said, never worked around."""


def nexus_scenario_hash() -> str:
    return hashlib.sha256(json.dumps(NEXUS_SCENARIO, sort_keys=True).encode()).hexdigest()


def start_week_for(warmup_week: int) -> int:
    """§27.2 rule 1: week 26, or the first week after warm-up when that is later."""
    return max(int(NEXUS_SCENARIO["start_week"]), int(warmup_week) + 1)


@dataclass(frozen=True)
class NexusTarget:
    kind: str   # "supplier" | "material"
    id: str


@dataclass
class NexusRow:
    target: NexusTarget
    by_duration: dict[int, dict]          # weeks → {mean, ci_halfwidth, n} of Δ € lost sales
    average_eur: float
    units_by_duration: dict[int, float]   # weeks → mean Δ lost units (stored, not ranked on)
    backlog_by_duration: dict[int, float] # weeks → mean Δ peak backlog (units)
    fill_rate_drop_by_duration: dict[int, float]  # weeks → mean (clean − cell) window fill rate
    zero_reason: Optional[str]
    rank: int = 0

    def as_dict(self) -> dict:
        return {
            "entity_type": self.target.kind,
            "entity_id": self.target.id,
            "metrics": {
                "rank": self.rank,
                "average_eur": self.average_eur,
                "by_duration": {str(d): v for d, v in self.by_duration.items()},
                "units_by_duration": {str(d): v for d, v in self.units_by_duration.items()},
                "backlog_by_duration": {str(d): v for d, v in self.backlog_by_duration.items()},
                "fill_rate_drop_by_duration": {str(d): v for d, v in self.fill_rate_drop_by_duration.items()},
                "zero_reason": self.zero_reason,
            },
        }


@dataclass
class NexusBattery:
    engine_version: str
    scenario_hash: str
    warmup_week: int
    start_week: int
    window_weeks: int
    replications: int
    clean_digest: str
    clean_lost_sales_eur: dict
    clean_fill_rate: dict
    rows: list[NexusRow] = field(default_factory=list)

    def summary(self) -> dict:
        """What the store keeps on the run (`row_counts`), beside the rows."""
        return {
            "engine_version": self.engine_version,
            "scenario": NEXUS_SCENARIO,
            "scenario_hash": self.scenario_hash,
            "warmup_week": self.warmup_week,
            "start_week": self.start_week,
            "window_weeks": self.window_weeks,
            "replications": self.replications,
            "clean_digest": self.clean_digest,
            "clean_lost_sales_eur": self.clean_lost_sales_eur,
            "clean_fill_rate": self.clean_fill_rate,
            "targets": len(self.rows),
            "materials": sum(r.target.kind == "material" for r in self.rows),
            "suppliers": sum(r.target.kind == "supplier" for r in self.rows),
        }

    def results(self) -> list[dict]:
        return [r.as_dict() for r in self.rows]


def all_targets(scenario: Scenario) -> list[NexusTarget]:
    net = scenario.network
    return ([NexusTarget("supplier", s.id) for s in net.suppliers]
            + [NexusTarget("material", m.id) for m in net.materials])


def run_nexus_battery(
    scenario: Scenario,
    targets: Optional[Iterable[NexusTarget]] = None,
    expected_warmup: Optional[int] = None,
    expected_clean_digest: Optional[str] = None,
) -> NexusBattery:
    """Run the battery over ``targets`` (default: every supplier and material)."""
    from scsim import ENGINE_VERSION
    from scsim.io.snapshots import SnapshotStore

    known = set(all_targets(scenario))
    chosen = list(targets) if targets is not None else sorted(known, key=_order_key_target)
    unknown = [t for t in chosen if t not in known]
    if unknown:
        raise NexusBatteryError(
            "not a supplier or supplied material of this scenario: "
            + ", ".join(f"{t.kind}:{t.id}" for t in unknown))

    # Fixed replications: a sequential rule would give a cell more replications
    # than its clean reference, and the pairing below needs the same ones.
    base = scenario.without_events(name=f"{scenario.name}__nexus_clean")
    base = base.model_copy(update={"settings": base.settings.model_copy(
        update={"replication_stopping": ReplicationStopping.FIXED})}, deep=True)
    snapshots = SnapshotStore()
    base_compiled = compile_scenario(base)
    warmup = resolve_warmup(base_compiled)
    t_w = int(warmup.adopted_week)
    if expected_warmup is not None and t_w != int(expected_warmup):
        raise NexusBatteryError(
            f"this shard's clean reference adopted warm-up week {t_w}, the battery's is "
            f"{expected_warmup} — the shards would not be one battery")
    settings = base.settings
    window_end = min(t_w + settings.analysis_window, settings.horizon)
    start = start_week_for(t_w)
    longest = max(NEXUS_SCENARIO["durations_weeks"])
    if start + longest > window_end:
        raise NexusBatteryError(
            f"a {longest}-week outage from week {start} ends after the KPI window "
            f"(weeks {t_w}–{window_end - 1}); lengthen the horizon or the analysis window")

    clean = run_scenario(base, compiled=base_compiled, snapshot_store=snapshots)
    clean_by_rep = {cell[0]: clean.kpis[r] for r, cell in enumerate(clean.rep_cells)}
    digest = _clean_digest(clean)
    if expected_clean_digest is not None and digest != expected_clean_digest:
        raise NexusBatteryError(
            "this shard's clean reference differs from the battery's (digest "
            f"{digest[:12]} ≠ {expected_clean_digest[:12]}) — not the same engine, data or policies")

    rows: list[NexusRow] = []
    for tgt in chosen:
        by_d: dict[int, dict] = {}
        units: dict[int, float] = {}
        backlog: dict[int, float] = {}
        fr_drop: dict[int, float] = {}
        for d in NEXUS_SCENARIO["durations_weeks"]:
            ev = DisruptionEvent(
                target_type=TargetType.NODE_SUPPLIER if tgt.kind == "supplier" else TargetType.NODE_MATERIAL,
                target_id=tgt.id, effect_type=EffectType.LEAD_TIME_EXTENSION,
                start=start, duration=int(d))
            sc = base.model_copy(update={"events": [ev],
                                         "name": f"{scenario.name}__nexus__{tgt.kind}__{tgt.id}__{d}w"},
                                 deep=True)
            sc_compiled = compile_scenario(sc)
            sc_compiled.warmup = warmup
            res = run_scenario(sc, compiled=sc_compiled, snapshot_store=snapshots)
            delta = _paired(res, clean_by_rep, "lost_sales_value")
            agg = aggregate_mean_ci(delta, float(settings.ci_level))
            by_d[int(d)] = {"mean": _r(agg["mean"]), "ci_halfwidth": _r(agg["ci_halfwidth"]),
                            "n": agg["n"]}
            units[int(d)] = _r(float(np.mean(_paired(res, clean_by_rep, "lost_units"))))
            backlog[int(d)] = _r(float(np.mean(_paired(res, clean_by_rep, "max_backlog"))))
            fr_drop[int(d)] = _r(-float(np.nanmean(_paired(res, clean_by_rep, "fill_rate"))))
        avg = _r(float(np.mean([v["mean"] for v in by_d.values()])))
        rows.append(NexusRow(tgt, by_d, avg, units, backlog, fr_drop, _zero_reason(by_d, backlog)))

    rank_rows(rows)
    return NexusBattery(
        engine_version=ENGINE_VERSION,
        scenario_hash=nexus_scenario_hash(),
        warmup_week=t_w,
        start_week=start,
        window_weeks=int(window_end - t_w),
        replications=len(clean.rep_cells),
        clean_digest=digest,
        clean_lost_sales_eur=_agg_dict(clean, "lost_sales_value"),
        clean_fill_rate=_agg_dict(clean, "fill_rate"),
        rows=rows,
    )


def rank_rows(rows: list[NexusRow]) -> None:
    """§27.2 rule 5, in place: Average desc, 9-week desc, kind, id. Also what
    merges shards: ranking the concatenation of shards' rows IS the full order."""
    longest = max(NEXUS_SCENARIO["durations_weeks"])
    rows.sort(key=lambda r: (-r.average_eur, -r.by_duration[longest]["mean"],
                             r.target.kind, r.target.id))
    for i, r in enumerate(rows, start=1):
        r.rank = i


def merge_shards(shard_results: Iterable[list[dict]]) -> list[dict]:
    """Concatenate shards' `results()` and re-rank them as one battery (rule 5).
    Refuses a target that appears twice — a shard ran twice, or two overlapped."""
    longest = str(max(NEXUS_SCENARIO["durations_weeks"]))
    rows = [r for shard in shard_results for r in shard]
    seen: set[tuple[str, str]] = set()
    for r in rows:
        key = (r["entity_type"], r["entity_id"])
        if key in seen:
            raise NexusBatteryError(f"{key[0]}:{key[1]} is in more than one shard")
        seen.add(key)
    rows = [{**r, "metrics": dict(r["metrics"])} for r in rows]
    rows.sort(key=lambda r: (-r["metrics"]["average_eur"],
                             -r["metrics"]["by_duration"][longest]["mean"],
                             r["entity_type"], r["entity_id"]))
    for i, r in enumerate(rows, start=1):
        r["metrics"]["rank"] = i
    return rows


def _order_key_target(t: NexusTarget) -> tuple[str, str]:
    return (t.kind, t.id)


def _paired(res, clean_by_rep: dict, kpi: str) -> np.ndarray:
    out = []
    for r, (i, _j) in enumerate(res.rep_cells):
        a, b = res.kpis[r].get(kpi, float("nan")), clean_by_rep[i].get(kpi, float("nan"))
        out.append(float(a) - float(b))
    return np.asarray(out, dtype=float)


def _zero_reason(by_d: dict[int, dict], backlog: dict[int, float]) -> Optional[str]:
    if any(v["mean"] > ZERO_EUR for v in by_d.values()):
        return None
    if any(b > ZERO_EUR for b in backlog.values()):
        # Unmet demand waited (P-C.1 backorder) rather than being lost.
        return "backordered"
    return "absorbed"


def _clean_digest(clean) -> str:
    rows = [{k: clean.kpis[r][k] for k in ("lost_sales_value", "lost_units", "max_backlog",
                                           "fill_rate", "revenue") if k in clean.kpis[r]}
            for r in range(len(clean.rep_cells))]
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()


def _agg_dict(res, kpi: str) -> dict:
    a = res.aggregates.get(kpi) or {}
    return {"mean": _r(a.get("mean", float("nan"))), "ci_halfwidth": _r(a.get("ci_halfwidth", 0.0))}


def _r(x: float) -> Optional[float]:
    """Rounded to 1e-6 and JSON-safe (NaN → None), so a stored row reads back as written."""
    x = float(x)
    return None if math.isnan(x) else round(x, 6)
