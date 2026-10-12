#!/usr/bin/env python3
"""Calibrate the material inventory-control policy (P-X.1 `type`) of one project
for a target fill rate, changing ONLY what /policies sets.

Two models are calibrated separately, on common random numbers:

    A  type = min_max   (reorder point: s = E[D]·T_s (+ SS), S = E[D]·(T_s + κ))
    B  type = mrp       (ordered from the plan: need over L + SS − on hand − on the way)

For each model: baseline at the current policy version → one-lever screening on a
coarse grid (paired seeds) → bisection on every lever that moves fill toward the
target → choose the passing setting with the lowest average stock value →
confirmation on a NEW seed set, which alone gives PASS/FAIL. Then A vs B paired,
and a "platform twin" run with the scenario's own frame for the page = run check.

What it never touches: the dataset (no `ss.with_tables`), the scenario row, any
item-master / lane / capacity / lead-time / price / reliability / demand override,
`backorder_allowed`, and `safety_stock_method` (not a POLICY_BUNDLE_KEYS key — the
stored method decides which safety-stock key is live, and is reported). Nothing is
written to the platform: the result is a change sheet and the new policy snapshot
per model, to be entered on /policies and saved as a new policy version.

Usage
-----
    export SURESUITE_API_KEY=sk_…           # personal key, read:data + read:policies
    python scripts/calibration/calibrate_inventory.py --project "Aumovio" --out calib/aumovio
    python scripts/calibration/calibrate_inventory.py --project "Project AA - ver3" --out calib/aa3

    # self-test of the harness on the bundled Example — 1P/2M/3S (offline, no key).
    # It exercises the pipeline only; its numbers are NOT a calibration of anything.
    python scripts/calibration/calibrate_inventory.py --example --out /tmp/calib-example

Run it from outside the repository root or with the packages installed (the repo's
`scsim/` folder shadows the installed package when the working directory is the
root) — the script removes the root from sys.path itself.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import sys
import time
from pathlib import Path
from typing import Any, Callable, Optional

ROOT = Path(__file__).resolve().parents[2]
for p in (str(ROOT), ""):
    while p in sys.path:
        sys.path.remove(p)

import numpy as np  # noqa: E402

# ── target ──────────────────────────────────────────────────────────────────────
LO, HI, AIM = 0.95, 0.98, 0.965
MAX_HALF_WIDTH = 0.015
MAX_REPS = 200  # the engine clamps replications to 1-200

# ── levers: (policy key, family, grid, bisection bounds, integer?, models, condition)
# Only POLICY_BUNDLE_KEYS keys at `default` scope. `condition(ctx)` says whether the
# mapper READS the key under the stored settings (e.g. safety_stock_days is read at
# default scope only with a fixed_days method), so an inert key is never "tuned".
SS_SERVICE = ("service_level", "demand_variability")


def _ss_method(ctx) -> str:
    return str(ctx["inventory"].get("safety_stock_method", "fixed_days"))


LEVERS: list[dict[str, Any]] = [
    {"key": "safety_stock_days", "family": "inventory", "grid": [0, 7, 14, 28, 42, 56, 84],
     "lo": 0, "hi": 84, "int": True, "models": ("min_max", "mrp"),
     "reads": lambda c: _ss_method(c) not in SS_SERVICE and _ss_method(c) != "king_method",
     "why_inert": "read at default scope only when safety_stock_method is fixed_days"},
    {"key": "service_level_target", "family": "inventory", "grid": [0.80, 0.90, 0.95, 0.98, 0.995],
     "lo": 0.80, "hi": 0.999, "int": False, "models": ("min_max", "mrp"),
     "reads": lambda c: _ss_method(c) in SS_SERVICE,
     "why_inert": "read only when safety_stock_method is service_level or demand_variability"},
    {"key": "coverage_weeks", "family": "inventory", "grid": [0, 0.5, 1, 2, 4, 8, 12, 16, 26],
     "lo": 0, "hi": 26, "int": False, "models": ("min_max",),
     "reads": lambda c: True, "why_inert": ""},
    {"key": "fg_safety_stock_days", "family": "inventory", "grid": [0, 3, 6, 9, 12],
     "lo": 0, "hi": 12, "int": True, "models": ("min_max", "mrp"),
     "reads": lambda c: c["mts"] and str(c["inventory"].get("fg_safety_stock", "fixed_days")) not in ("none", "service_level"),
     "why_inert": "P-P.4 runs for MTS products only, and reads days only with fixed_days sizing"},
    {"key": "fg_service_level_target", "family": "inventory", "grid": [0.80, 0.90, 0.95, 0.98, 0.995],
     "lo": 0.80, "hi": 0.999, "int": False, "models": ("min_max", "mrp"),
     "reads": lambda c: c["mts"] and str(c["inventory"].get("fg_safety_stock", "")) == "service_level",
     "why_inert": "P-P.4 runs for MTS products only, and reads it only with service_level sizing"},
]

# Keys this script refuses to write — facts about the world, or what "fill rate" means.
FORBIDDEN = {"capacity_per_week", "production_capacity", "capacity_units_per_day", "lead_time_weeks",
             "lane_lead_time_dist", "lane_lead_time_cv", "lane_lead_time_min_weeks",
             "lane_lead_time_mode_weeks", "lane_lead_time_max_weeks", "material_cost", "material_moq",
             "sell_price", "reliability_score", "backorder_allowed", "row_demand_mode",
             "row_demand_schedule", "row_demand_distribution", "row_demand_mean",
             "row_demand_variation", "row_demand_min", "row_demand_max", "safety_stock_method"}

KPIS = ["fill_rate", "lost_units", "lost_sales_value", "avg_on_hand_value", "avg_fg_value",
        "avg_on_hand_units", "avg_fg_units", "cost_ss_holding", "cost_fg_ss_holding",
        "products_capacity_bound", "suppliers_capacity_bound", "capacity_utilization",
        "supplier_capacity_utilization", "material_shortage_weeks", "mrp_late_receipt_weeks",
        "lost_inbound_units", "max_backlog"]


# ── statistics ──────────────────────────────────────────────────────────────────
def t_crit(df: int) -> float:
    """Two-sided 95 % Student t critical value (no scipy dependency)."""
    table = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306,
             9: 2.262, 10: 2.228, 12: 2.179, 15: 2.131, 20: 2.086, 25: 2.060, 29: 2.045,
             30: 2.042, 40: 2.021, 60: 2.000, 120: 1.980}
    if df in table:
        return table[df]
    keys = sorted(table)
    if df > keys[-1]:
        return 1.960
    lo = max(k for k in keys if k < df)
    hi = min(k for k in keys if k > df)
    return table[lo] + (table[hi] - table[lo]) * (df - lo) / (hi - lo)


def mean_ci(x) -> dict:
    x = np.asarray([v for v in x if v is not None and not (isinstance(v, float) and math.isnan(v))], float)
    n = len(x)
    if n == 0:
        return {"n": 0, "mean": None, "hw": None, "lo": None, "hi": None, "sd": None}
    m = float(x.mean())
    sd = float(x.std(ddof=1)) if n > 1 else 0.0
    hw = t_crit(n - 1) * sd / math.sqrt(n) if n > 1 else float("inf")
    return {"n": n, "mean": m, "hw": hw, "lo": m - hw, "hi": m + hw, "sd": sd}


def verdict(ci: dict) -> str:
    if ci["mean"] is None:
        return "FAIL (no replications)"
    inside = ci["lo"] >= LO and ci["hi"] <= HI
    if inside and ci["hw"] < MAX_HALF_WIDTH:
        return "PASS"
    why = []
    if ci["lo"] < LO:
        why.append(f"CI lower {ci['lo']:.4f} < {LO}")
    if ci["hi"] > HI:
        why.append(f"CI upper {ci['hi']:.4f} > {HI}")
    if ci["hw"] >= MAX_HALF_WIDTH:
        why.append(f"half-width {ci['hw']*100:.2f} pp ≥ {MAX_HALF_WIDTH*100:.1f} pp")
    return "FAIL (" + "; ".join(why) + ")"


def pair_key(r: dict) -> str:
    k = r.get("kpis") or {}
    return f"m{int(k.get('model_rep') or 0)}:e{int(k.get('event_rep') or 0)}"


def paired(reps_a: list, reps_b: list, kpi: str) -> dict:
    """B − A, paired on the common-random-numbers cell."""
    a = {pair_key(r): (r.get("kpis") or {}).get(kpi) for r in reps_a}
    d = [(r.get("kpis") or {}).get(kpi) - a[pair_key(r)] for r in reps_b
         if pair_key(r) in a and a[pair_key(r)] is not None and (r.get("kpis") or {}).get(kpi) is not None]
    ci = mean_ci(d)
    ci["call"] = ("no clear difference" if ci["n"] < 2 or (ci["lo"] <= 0 <= ci["hi"])
                  else ("B higher" if ci["mean"] > 0 else "A higher"))
    return ci


# ── engine access ───────────────────────────────────────────────────────────────
class Session:
    """One project: frozen dataset + policy version + scenario frame, and a run cache."""

    def __init__(self, dataset_snapshot: dict, policy_snapshot: dict, scenario: Optional[dict],
                 project_model: Optional[str], meta: dict, log: Callable[[str], None]):
        self.dataset = dataset_snapshot
        self.policy = policy_snapshot
        self.scenario = scenario or {}
        self.project_model = project_model
        self.meta = meta
        self.log = log
        self.runs = 0
        self.code_version: Optional[str] = None

    def frame(self, platform: bool = False, **over) -> dict:
        """The scenario's frame. `platform=True` is exactly what Run & validate runs;
        otherwise common random numbers are forced on and a sequential stopping rule
        is dropped, so every calibration run has the fixed n it asks for."""
        from suresuite.local import DEFAULT_FRAME
        keep = ("horizon_days", "warmup_days", "warmup_mode", "replications", "seed", "crn",
                "disruption_schedule", "stopping_rule", "demand_model", "recovery_overrides")
        sc = {**DEFAULT_FRAME, **{k: v for k, v in self.scenario.items() if k in keep and v is not None}}
        if not platform:
            sc["crn"] = True
            sc.pop("stopping_rule", None)
        sc.update(over)
        return sc

    def run(self, policy_snapshot: dict, frame: dict, inspection: bool = False) -> dict:
        from sim_worker.local import run_from_snapshots
        sc = {**frame}
        if inspection:
            sc.update(replications=1, inspection=True)
        t0 = time.time()
        out = run_from_snapshots(self.dataset, policy_snapshot, sc, project_model=self.project_model)
        self.runs += 1
        cv = out["run_update"].get("code_version")
        if self.code_version and cv and cv != self.code_version:
            raise SystemExit(f"engine build changed mid-calibration: {self.code_version} → {cv}")
        self.code_version = self.code_version or cv
        self.log(f"    run #{self.runs}: {sc.get('replications')} reps, seed {sc.get('seed')}, "
                 f"{time.time() - t0:.1f}s")
        return out


def summarize(out: dict) -> dict:
    reps = [r for r in out["replications"] if r.get("status", "done") == "done"]
    s = {k: mean_ci([(r.get("kpis") or {}).get(k) for r in reps]) for k in KPIS}
    stock = [((r.get("kpis") or {}).get("avg_on_hand_value") or 0.0) + ((r.get("kpis") or {}).get("avg_fg_value") or 0.0)
             for r in reps]
    s["avg_stock_value"] = mean_ci(stock)
    agg = out["run_update"].get("aggregate_kpis") or {}
    s["_capacity_binding"] = (agg.get("_meta") or {}).get("capacity_binding")
    s["_warmup_at"] = sorted({r.get("warmup_at") for r in reps if r.get("warmup_at") is not None})
    s["_order_cv"] = order_cv(out)
    return s


def order_cv(out: dict) -> Optional[float]:
    """CV of the weekly total material-order quantity, from inspection series if present."""
    items = [x for x in (out.get("item_series") or []) if x.get("kind") == "material"]
    if not items:
        return None
    tot = np.sum([np.asarray(x["series"].get("orders") or [], float) for x in items], axis=0)
    return float(tot.std(ddof=1) / tot.mean()) if tot.size > 1 and tot.mean() > 0 else None


def with_policy(base: dict, model: str, sets: dict[str, Any]) -> tuple[dict, list[str]]:
    """A copy of a v2 policy snapshot with the default inventory `type` fixed to `model`,
    supplier-row `type` overrides aligned to it, and `sets` written at default scope."""
    for k in sets:
        if k in FORBIDDEN:
            raise ValueError(f"refusing to set {k}: it overrides a fact or the unmet-demand rule")
    snap = copy.deepcopy(base)
    if "defaults" not in snap:  # v1 → v2 shape (snapshot_to_policies reads both)
        snap = {"schema_version": 2, "defaults": {k: v for k, v in snap.items() if isinstance(v, dict)},
                "overrides": []}
    d = snap.setdefault("defaults", {})
    inv = d.setdefault("inventory", {})
    inv["type"] = model
    for k, v in sets.items():
        fam = next((lv["family"] for lv in LEVERS if lv["key"] == k), "inventory")
        d.setdefault(fam, {})[k] = v
    aligned = []
    for row in snap.get("overrides") or []:
        p = row.get("patch") or {}
        if row.get("family") == "inventory" and "type" in p and p["type"] != model:
            aligned.append(f"{row.get('scope', 'node')}:{row.get('target_key')} type {p['type']} → {model}")
            p["type"] = model
    return snap, aligned


# ── pre-flight ──────────────────────────────────────────────────────────────────
def preflight(sess: Session) -> dict:
    from scsim.io.project_map import _rate_to_weekly, _resolve_demand_kind
    from sim_worker.local import dataset_inputs
    t = dataset_inputs(sess.dataset)
    pol = sess.policy.get("defaults", sess.policy)
    ful = pol.get("fulfillment") or {}
    bo = ful.get("backorder_allowed")
    row_bo = [f"{r.get('scope')}:{r.get('target_key')} = {r['patch']['backorder_allowed']}"
              for r in sess.policy.get("overrides") or []
              if r.get("family") == "fulfillment" and "backorder_allowed" in (r.get("patch") or {})]
    sc_model = sess.scenario.get("demand_model") or {}
    demand = []
    out_by_prod: dict[str, float] = {}
    for o in t["outbound"]:
        pid = str(o.get("product_id") or "")
        v = o.get("volume")
        if pid and v is not None:
            out_by_prod[pid] = out_by_prod.get(pid, 0.0) + _rate_to_weekly(float(v), o.get("time_unit"))
    for p in t["products"]:
        pid = str(p.get("product_id"))
        dm = p.get("demand_mean")
        kind = _resolve_demand_kind(p.get("demand_distribution"), sc_model)
        src = ("product demand_distribution" if p.get("demand_distribution")
               else "scenario demand_model.kind" if sc_model.get("kind") else "engine fallback (triangular)")
        out_w = out_by_prod.get(pid)
        used = float(dm) if dm is not None and float(dm) > 0 else out_w
        demand.append({"product_id": pid, "distribution": kind, "distribution_source": src,
                       "demand_mean": dm, "outbound_weekly_sum": out_w,
                       "engine_weekly_demand": used,
                       "engine_reads": "demand_mean" if dm is not None and float(dm) > 0 else "Σ weekly outbound",
                       "differs": (dm is not None and out_w is not None and abs(float(dm) - out_w) > 1e-6 * max(1.0, out_w))})
    lanes_no_lt = [f"{r.get('supplier_id')}→{r.get('material_id')}" for r in t["inbound"] if r.get("lead_time") in (None, "")]
    lanes_no_price = [f"{r.get('supplier_id')}→{r.get('material_id')}" for r in t["inbound"] if r.get("unit_price") in (None, "")]
    caps = [{"supplier_id": s.get("supplier_id"), "capacity_per_week": s.get("capacity_per_week")}
            for s in t["suppliers"] if s.get("capacity_per_week") not in (None, "")]
    pcaps = [{"product_id": p.get("product_id"), "production_capacity": p.get("production_capacity")}
             for p in t["products"] if p.get("production_capacity") not in (None, "")]
    inv = pol.get("inventory") or {}
    return {
        "unmet_demand_rule": {
            "stored_backorder_allowed": bo,
            "engine_rule": ("backorder" if bo is True else "lost sales" if bo is False
                            else "lost sales (key absent — the engine's default; D204 a)"),
            "customer_row_overrides": row_bo,
        },
        "stored_inventory_defaults": inv,
        "safety_stock_method": inv.get("safety_stock_method", "fixed_days (absent → mapper default)"),
        "row_overrides_in_version": len(sess.policy.get("overrides") or []),
        "demand": demand,
        "lanes_without_lead_time": lanes_no_lt,
        "lanes_without_price": lanes_no_price,
        "supplier_capacities": caps,
        "product_capacities": pcaps,
        "counts": {k: len(v) for k, v in t.items()},
    }


def warmup_week(series: dict, horizon_weeks: int) -> dict:
    """scsim.stats.warmup on the replication-mean weekly fill-rate series."""
    from scsim.stats.warmup import WarmupMethod, detect_warmup
    import pandas as pd
    df = pd.DataFrame(series)
    if df.empty or "fill_rate" not in df:
        return {"adopted_week": None}
    mean_series = df.groupby("week")["fill_rate"].mean().sort_index().to_numpy()
    rep = detect_warmup(mean_series, WarmupMethod.MOST_CONSERVATIVE)
    return {"adopted_week": int(rep.adopted_week), "conway_week": int(rep.conway_week),
            "mser5_week": int(rep.mser5_week), "method": "most_conservative (scsim.stats.warmup)",
            "series": "replication-mean weekly fill_rate", "horizon_weeks": horizon_weeks}


def diagnostics(sess: Session, pol: dict, frame: dict, seeds: list[int]) -> dict:
    """Per-item shortfall from single-replication inspection runs (the engine's
    per-item series exist only in inspection mode)."""
    lost: dict[str, float] = {}
    demand: dict[str, float] = {}
    starve: dict[str, int] = {}
    w0 = int(round(frame.get("warmup_days", 0) / 7)) if frame.get("warmup_mode") == "manual" else 0
    for s in seeds:
        out = sess.run(pol, {**frame, "seed": s}, inspection=True)
        for x in out.get("item_series") or []:
            ser = x["series"]
            if x["kind"] == "product":
                pid = x["item_id"]
                lost[pid] = lost.get(pid, 0.0) + float(np.sum(ser.get("lost_units", [])[w0:]))
                demand[pid] = demand.get(pid, 0.0) + float(np.sum(ser.get("demand", [])[w0:]))
                bl = ser.get("backlog") or []
                if bl:  # under backorders the shortfall is the backlog, not lost units
                    lost[f"{pid} (end backlog)"] = lost.get(f"{pid} (end backlog)", 0.0) + float(bl[-1])
            elif x["kind"] == "material":
                oh = np.asarray(ser.get("on_hand") or [], float)[w0:]
                starve[x["item_id"]] = starve.get(x["item_id"], 0) + int(np.sum(oh <= 1e-6))
    n = max(len(seeds), 1)
    tot = sum(v for k, v in lost.items() if "(end backlog)" not in k) or 0.0
    by_item = sorted(((k, v / n) for k, v in lost.items() if v > 0), key=lambda kv: -kv[1])
    return {
        "inspection_seeds": seeds,
        "lost_units_per_rep_by_product": [{"product_id": k, "units": round(v, 2),
                                           "share": (round(v * n / tot, 3) if tot and "(end backlog)" not in k else None),
                                           "demand_per_rep": round(demand.get(k, 0.0) / n, 2) if k in demand else None}
                                          for k, v in by_item],
        "zero_stock_weeks_per_rep_by_material": [{"material_id": k, "weeks": round(v / n, 2)}
                                                 for k, v in sorted(starve.items(), key=lambda kv: -kv[1]) if v > 0][:25],
    }


# ── calibration of one model ───────────────────────────────────────────────────
def calibrate_model(sess: Session, model: str, ctx: dict, frame: dict, seeds: dict, reps: int,
                    screen_reps: int, log) -> dict:
    res: dict[str, Any] = {"model": model}
    base_pol, aligned = with_policy(sess.policy, model, {})
    res["type_rows_aligned"] = aligned
    log(f"  [{model}] baseline ({reps} reps)")
    base_out = sess.run(base_pol, {**frame, "replications": reps, "seed": seeds["search"]})
    res["baseline"] = summarize(base_out)
    insp = sess.run(base_pol, {**frame, "seed": seeds["search"]}, inspection=True)
    res["baseline"]["_order_cv"] = order_cv(insp)

    # screening — one lever at a time, paired against the baseline's first `screen_reps` cells
    screen_frame = {**frame, "replications": screen_reps, "seed": seeds["search"]}
    s_base = sess.run(base_pol, screen_frame)
    levers = [lv for lv in LEVERS if model in lv["models"]]
    res["inert_levers"] = [{"key": lv["key"], "why": lv["why_inert"]} for lv in levers if not lv["reads"](ctx)]
    levers = [lv for lv in levers if lv["reads"](ctx)]
    screening = []
    cache: dict[tuple, dict] = {}

    def point(sets: dict, n: int, seed: int) -> dict:
        ck = (tuple(sorted(sets.items())), n, seed)
        if ck not in cache:
            pol, _ = with_policy(sess.policy, model, sets)
            out = sess.run(pol, {**frame, "replications": n, "seed": seed})
            cache[ck] = {"sets": dict(sets), "summary": summarize(out), "reps": out["replications"], "policy": pol}
        return cache[ck]

    def fill_at(sets: dict) -> Optional[float]:
        return point(sets, screen_reps, seeds["search"])["summary"]["fill_rate"]["mean"]

    log(f"  [{model}] screening {len(levers)} lever(s), {screen_reps} reps each point")
    for lv in levers:
        rows = []
        for v in lv["grid"]:
            p = point({lv["key"]: v}, screen_reps, seeds["search"])
            d = paired(s_base["replications"], p["reps"], "fill_rate")
            rows.append({"value": v, "fill": p["summary"]["fill_rate"]["mean"],
                         "stock": p["summary"]["avg_stock_value"]["mean"],
                         "d_fill_vs_base": d["mean"], "d_fill_hw": d["hw"]})
        fills = [r["fill"] for r in rows if r["fill"] is not None]
        screening.append({"key": lv["key"], "grid": rows,
                          "range_of_effect": (max(fills) - min(fills)) if fills else 0.0})
    screening.sort(key=lambda s: -s["range_of_effect"])
    res["screening"] = screening

    def bracket(lv: dict, fixed: dict, rows: list[dict]) -> Optional[tuple]:
        """Bisection on one lever (others `fixed`) toward AIM on a response that is
        monotone in expectation: the largest value below AIM and the smallest above."""
        above = [r["value"] for r in rows if r["fill"] is not None and r["fill"] >= AIM]
        if not above:
            return None
        hi_v = min(above)
        below = [r["value"] for r in rows if r["fill"] is not None and r["fill"] < AIM and r["value"] < hi_v]
        lo_v = max(below) if below else lv["lo"]
        tol = 1 if lv["int"] else (0.0025 if lv["hi"] <= 1 else 0.25)
        for _ in range(10):
            if hi_v - lo_v <= tol:
                break
            mid = (lo_v + hi_v) / 2
            mid = int(round(mid)) if lv["int"] else round(mid, 4)
            if mid in (lo_v, hi_v):
                break
            f = fill_at({**fixed, lv["key"]: mid})
            if f is not None and f >= AIM:
                hi_v = mid
            else:
                lo_v = mid
        return lo_v, hi_v

    candidates = []

    def add_full(sets: dict):
        if any(c["sets"] == sets for c in candidates):
            return
        p = point(sets, reps, seeds["search"])
        candidates.append({"sets": dict(sets), "summary": p["summary"], "policy": p["policy"],
                           "verdict_search": verdict(p["summary"]["fill_rate"])})

    # search 1 — each effective lever alone
    effective = [sc for sc in screening if sc["range_of_effect"] >= 1e-4]
    one_d: dict[str, tuple] = {}
    for sc in effective:
        lv = next(lv for lv in levers if lv["key"] == sc["key"])
        br = bracket(lv, {}, sc["grid"])
        if br is None:
            log(f"  [{model}] {lv['key']}: aim {AIM} not reached even at {sc['grid'][-1]['value']}")
            continue
        one_d[lv["key"]] = br
        for v in sorted(set(br)):
            add_full({lv["key"]: v})

    # search 2 — the two strongest levers together: for each value of the first at or
    # below its one-lever solution, bisect the second (stock from two buffers is rarely
    # cheapest at a corner)
    if len(effective) >= 2:
        la = next(lv for lv in levers if lv["key"] == effective[0]["key"])
        lb = next(lv for lv in levers if lv["key"] == effective[1]["key"])
        cap = one_d.get(la["key"], (None, la["hi"]))[1]
        for a in [v for v in la["grid"] if v <= cap][:4]:
            rows = [{"value": v, "fill": fill_at({la["key"]: a, lb["key"]: v})} for v in (lb["lo"], lb["hi"])]
            br = bracket(lb, {la["key"]: a}, rows)
            if br is not None:
                add_full({la["key"]: a, lb["key"]: br[1]})

    passing = [c for c in candidates if c["verdict_search"] == "PASS"]
    res["search_candidates"] = [{"sets": c["sets"], "verdict_search": c["verdict_search"],
                                 "fill": c["summary"]["fill_rate"], "stock": c["summary"]["avg_stock_value"]["mean"]}
                                for c in candidates]
    # Baseline itself may already pass — it is a candidate with no change.
    if verdict(res["baseline"]["fill_rate"]) == "PASS":
        passing.append({"sets": {}, "summary": res["baseline"], "policy": base_pol, "verdict_search": "PASS"})
    if not passing:
        res["chosen"] = None
        # the setting closest to the aim (a shortfall, or an overshoot no lever can lower)
        best = min(candidates or [{"summary": res["baseline"], "sets": {}, "policy": base_pol}],
                   key=lambda c: abs((c["summary"]["fill_rate"]["mean"] or 0) - AIM))
        res["binding"] = binding_constraint(sess, best, frame, seeds, model, log)
        res["verdict"] = "FAIL (no policy setting in the searched space reaches the window)"
        return res
    chosen = min(passing, key=lambda c: c["summary"]["avg_stock_value"]["mean"])
    res["chosen"] = {"sets": chosen["sets"]}
    res["policy"] = chosen["policy"]

    # confirmation — NEW seeds; the only run the verdict comes from
    n = reps
    while True:
        log(f"  [{model}] confirmation ({n} reps, seed {seeds['confirm']})")
        conf = sess.run(chosen["policy"], {**frame, "replications": n, "seed": seeds["confirm"]})
        cs = summarize(conf)
        ci = cs["fill_rate"]
        need = n if ci["hw"] < MAX_HALF_WIDTH else math.ceil(n * (ci["hw"] / (0.9 * MAX_HALF_WIDTH)) ** 2)
        if need <= n or n >= MAX_REPS:
            break
        n = min(need, MAX_REPS)
    res["confirmation"] = cs
    res["confirmation_reps"] = conf["replications"]
    res["confirmation_n"] = n
    res["verdict"] = verdict(cs["fill_rate"])
    if res["verdict"] != "PASS":
        res["binding"] = binding_constraint(sess, chosen, frame, seeds, model, log)
    return res


def binding_constraint(sess: Session, cand: dict, frame: dict, seeds: dict, model: str, log) -> dict:
    log(f"  [{model}] diagnosing the binding constraint")
    s = cand["summary"]
    diag = diagnostics(sess, cand["policy"], frame, [seeds["search"] + i for i in range(5)])
    return {
        "at_setting": cand.get("sets") or "the current policy",
        "fill_rate": s["fill_rate"],
        "products_capacity_bound_weeks": s["products_capacity_bound"]["mean"],
        "suppliers_capacity_bound_weeks": s["suppliers_capacity_bound"]["mean"],
        "material_shortage_weeks": s["material_shortage_weeks"]["mean"],
        "lost_units": s["lost_units"]["mean"],
        "capacity_binding": s["_capacity_binding"],
        **diag,
    }


# ── report ─────────────────────────────────────────────────────────────────────
def fmt_ci(ci: dict, pct=True) -> str:
    if not ci or ci.get("mean") is None:
        return "—"
    f = (lambda v: f"{v*100:.2f}%") if pct else (lambda v: f"{v:,.1f}")
    return f"{f(ci['mean'])} [{f(ci['lo'])}, {f(ci['hi'])}]"


def report(proj: dict, sess: Session, pf: dict, wu: dict, frame: dict, seeds: dict, models: dict,
           ab: Optional[dict], twins: dict, today: str) -> str:
    L = [f"# Inventory-policy calibration — {proj.get('name')}", "",
         f"Computed {today} with scripts/calibration/calibrate_inventory.py. Every number below is "
         "from a run of the engine on the frozen versions named in the reproducibility block.", ""]
    L += ["## Results", "",
          "| model | baseline fill [95% CI] | calibrated fill [95% CI] | n | lost units | avg stock value | PASS/FAIL |",
          "|---|---|---|---|---|---|---|"]
    for m, r in models.items():
        c = r.get("confirmation")
        L.append(f"| {m} | {fmt_ci(r['baseline']['fill_rate'])} | {fmt_ci(c['fill_rate']) if c else '—'} | "
                 f"{r.get('confirmation_n', '—')} | {fmt_ci(c['lost_units'], False) if c else fmt_ci(r['baseline']['lost_units'], False)} | "
                 f"{fmt_ci(c['avg_stock_value'], False) if c else '—'} | {r['verdict']} |")
    L += ["", "Baseline detail (current policy, type fixed per model):", "",
          "| model | lost units | avg material stock value | avg FG stock value | order CV (1 inspection rep) |",
          "|---|---|---|---|---|"]
    for m, r in models.items():
        b = r["baseline"]
        L.append(f"| {m} | {fmt_ci(b['lost_units'], False)} | {fmt_ci(b['avg_on_hand_value'], False)} | "
                 f"{fmt_ci(b['avg_fg_value'], False)} | {b['_order_cv'] if b['_order_cv'] is None else round(b['_order_cv'], 3)} |")
    if ab:
        L += ["", "## A vs B (paired, confirmation seeds; B − A)", "",
              "| measure | Δ mean [95% CI] | call |", "|---|---|---|"]
        for k, d in ab.items():
            L.append(f"| {k} | {d['mean']:.4f} [{d['lo']:.4f}, {d['hi']:.4f}] | {d['call']} |")
    L += ["", "## /policies change sheet", "",
          "| model | stage tab | row | column (policy key) | current → new | reason |", "|---|---|---|---|---|---|"]
    cur = sess.policy.get("defaults", {}).get("inventory", {})
    for m, r in models.items():
        L.append(f"| {m} | Project defaults | default | type | {cur.get('type', '(unset → min_max)')} → {m} | the model under test (P-X.1) |")
        for a in r.get("type_rows_aligned") or []:
            L.append(f"| {m} | Supplier | {a.split(' type ')[0]} | type | {a.split(' type ')[1]} | one model per version |")
        for k, v in ((r.get("chosen") or {}).get("sets") or {}).items():
            L.append(f"| {m} | Project defaults | default | {k} | {cur.get(k, '(unset)')} → {v} | "
                     f"lowest-stock setting whose CI fell inside [{LO}, {HI}] on the search seeds |")
        L.append(f"| {m} | — | — | (save) | — | new policy version \"Calibrated {m} {today}\" |")
    L += ["", "## Pre-flight (data findings — reported, not fixed)", "",
          f"- Unmet-demand rule: **{pf['unmet_demand_rule']['engine_rule']}** (stored `backorder_allowed` = "
          f"{pf['unmet_demand_rule']['stored_backorder_allowed']}); customer-row overrides: "
          f"{pf['unmet_demand_rule']['customer_row_overrides'] or 'none'}.",
          f"- Safety-stock method (stored, not changed): `{pf['safety_stock_method']}`.",
          f"- Lanes without lead time (engine uses 2 weeks): {len(pf['lanes_without_lead_time'])} "
          f"{pf['lanes_without_lead_time'][:40]}",
          f"- Lanes without price (engine uses 1.0): {len(pf['lanes_without_price'])} {pf['lanes_without_price'][:40]}",
          "", "| product | distribution (source) | demand_mean | Σ weekly outbound | engine reads | differs |",
          "|---|---|---|---|---|---|"]
    for d in pf["demand"]:
        L.append(f"| {d['product_id']} | {d['distribution']} ({d['distribution_source']}) | {d['demand_mean']} | "
                 f"{None if d['outbound_weekly_sum'] is None else round(d['outbound_weekly_sum'], 3)} | {d['engine_reads']} | {d['differs']} |")
    for m, r in models.items():
        if r.get("binding"):
            b = r["binding"]
            L += ["", f"## Binding constraint — {m}", "", "```json", json.dumps(b, indent=2, default=str)[:6000], "```"]
        if r.get("inert_levers"):
            L += ["", f"Levers not tuned for {m} because the engine does not read them under the stored settings: "
                  + "; ".join(f"`{x['key']}` ({x['why']})" for x in r["inert_levers"])]
    L += ["", "## Page = run check", "",
          "Run each saved version once on the platform (Run & validate, the scenario below, its own frame) "
          "and compare with the local twin computed here on the same frame:", "",
          "| model | local twin fill [95% CI] | n | seed |", "|---|---|---|---|"]
    for m, t in twins.items():
        L.append(f"| {m} | {fmt_ci(t['fill_rate'])} | {t['fill_rate']['n']} | {t['_seed']} |")
    L += ["", "## Reproducibility", "", "```json", json.dumps({
        "project": {"id": proj.get("id"), "name": proj.get("name"), "supply_chain_model": sess.project_model},
        **sess.meta, "engine_code_version": sess.code_version, "scenario": {k: sess.scenario.get(k) for k in (
            "id", "name", "horizon_days", "warmup_mode", "warmup_days", "replications", "seed", "demand_model")},
        "calibration_frame": frame, "seeds": seeds, "warmup": wu, "engine_runs": sess.runs,
    }, indent=2, default=str), "```", "",
        "New policy snapshots: `policy_<model>.json` beside this report."]
    return "\n".join(L)


# ── main ───────────────────────────────────────────────────────────────────────
def load_live(args):
    import suresuite as ss
    api = ss.connect()
    ss.install_engine(api)
    projects = api.projects()
    proj = next((p for p in projects if args.project in (p.get("id"), p.get("name"))), None)
    if proj is None:
        names = ", ".join(sorted(str(p.get("name")) for p in projects))
        raise SystemExit(f"no project '{args.project}' visible to this key; it sees: {names}")
    pid = proj["id"]
    data = ss.dataset(api, pid, args.dataset_version)
    pol = ss.policy(api, pid, args.policy_version)
    scs = api.scenarios(pid)
    if args.scenario:
        sc = next((s for s in scs if args.scenario in (s.get("id"), s.get("name"))), None)
        if sc is None:
            raise SystemExit(f"no scenario '{args.scenario}'; the project has: " + ", ".join(s.get("name", "?") for s in scs))
    else:  # newest scenario with no disruption schedule; never create one (that writes)
        calm = [s for s in scs if not s.get("disruption_schedule")]
        sc = max(calm, key=lambda s: s.get("created_at") or "") if calm else None
    meta = {"dataset_version": {"id": data.id, "version_no": data.version_no, "label": data.label,
                                "graph_hash": data.graph_hash},
            "baseline_policy_version": {"id": pol.id, "label": pol.label, "policy_hash": pol.policy_hash}}
    return proj, data.snapshot, pol.snapshot, sc, proj.get("supply_chain_model"), meta


def load_example():
    ds = json.loads((ROOT / "scripts" / "example_project" / "dataset.json").read_text())
    tables = {k: ds[k] for k in ("suppliers", "materials", "products", "bom", "inbound", "outbound")}
    gh = hashlib.sha256(json.dumps(tables, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    pol = {"schema_version": 2, "defaults": {}, "overrides": []}
    meta = {"dataset_version": {"id": None, "label": "Example — 1P/2M/3S (local file)", "graph_hash": gh},
            "baseline_policy_version": {"id": None, "label": "empty defaults", "policy_hash": None}}
    proj = {"id": None, "name": "Example — 1P/2M/3S (harness self-test)"}
    return proj, {"schema_version": 2, "inputs": tables}, pol, None, "Make-To-Order", meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", help="project id or exact name")
    ap.add_argument("--example", action="store_true", help="offline self-test on the bundled example project")
    ap.add_argument("--scenario", help="scenario id or name (default: newest without disruptions)")
    ap.add_argument("--dataset-version", default="latest")
    ap.add_argument("--policy-version", default="latest")
    ap.add_argument("--models", default="min_max,mrp")
    ap.add_argument("--reps", type=int, default=30, help="baseline / full-check / confirmation replications (≥ 30)")
    ap.add_argument("--screen-reps", type=int, default=10, help="pilot replications per screening point")
    ap.add_argument("--seed", type=int, default=20261012, help="search seed (paired across models and candidates)")
    ap.add_argument("--confirm-seed", type=int, default=91081, help="NEW seed set for the confirmation run")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if args.reps < 30:
        ap.error("--reps must be ≥ 30")
    if not (args.project or args.example):
        ap.error("--project or --example")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    log_f = (out_dir / "calibration.log").open("w")

    def log(msg: str):
        print(msg, flush=True)
        log_f.write(msg + "\n")
        log_f.flush()

    proj, ds_snap, pol_snap, scenario, pmodel, meta = load_example() if args.example else load_live(args)
    sess = Session(ds_snap, pol_snap, scenario, pmodel, meta, log)
    today = dt.date.today().isoformat()
    log(f"project {proj.get('name')} · model {pmodel} · scenario {(scenario or {}).get('name', '(none — library default frame)')}")
    log(f"dataset {meta['dataset_version']} · policy {meta['baseline_policy_version']}")

    pf = preflight(sess)
    (out_dir / "preflight.json").write_text(json.dumps(pf, indent=2, default=str))
    log(f"pre-flight: unmet demand = {pf['unmet_demand_rule']['engine_rule']}; "
        f"{len(pf['lanes_without_lead_time'])} lanes w/o lead time; {len(pf['lanes_without_price'])} w/o price")

    seeds = {"search": args.seed, "confirm": args.confirm_seed}
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    # warm-up: scsim.stats.warmup on each model's baseline mean series; the larger is pinned
    base_frame = sess.frame(warmup_mode="auto")
    horizon_w = int(base_frame.get("horizon_days", 364)) // 7
    wus = {}
    for m in models:
        pol, _ = with_policy(pol_snap, m, {})
        out = sess.run(pol, {**base_frame, "replications": args.reps, "seed": seeds["search"]})
        wus[m] = warmup_week(out["series"], horizon_w)
        log(f"warm-up [{m}]: {wus[m]}")
    adopted = max((w["adopted_week"] or 0) for w in wus.values())
    wu = {"per_model": wus, "adopted_week": adopted, "pinned_as": f"warmup_mode=manual, warmup_days={adopted * 7}"}
    frame = sess.frame(warmup_mode="manual", warmup_days=adopted * 7)
    for k in ("replications", "seed"):  # set per run: n and the paired seed set
        frame.pop(k, None)

    ctx = {"inventory": (pol_snap.get("defaults") or {}).get("inventory") or {},
           "mts": str(pmodel or "").lower().replace("-", "_") in ("make_to_stock", "mts")}
    results = {}
    for m in models:
        log(f"model {m}")
        results[m] = calibrate_model(sess, m, ctx, frame, seeds, args.reps, args.screen_reps, log)
        if results[m].get("policy"):
            (out_dir / f"policy_{m}.json").write_text(json.dumps(results[m]["policy"], indent=2))

    ab = None
    if all(results[m].get("confirmation_reps") for m in models) and len(models) == 2:
        a, b = (results[m]["confirmation_reps"] for m in models)
        ab = {k: paired(a, b, k) for k in ("fill_rate", "lost_units", "avg_on_hand_value", "avg_fg_value")}

    # platform twin: the new version on the scenario's OWN frame (what Run & validate runs)
    twins = {}
    for m in models:
        if results[m].get("policy"):
            tf = sess.frame(platform=True)
            out = sess.run(results[m]["policy"], tf)
            twins[m] = {**summarize(out), "_seed": tf.get("seed")}

    def strip(r):
        return {k: v for k, v in r.items() if k not in ("confirmation_reps", "policy")}
    (out_dir / "results.json").write_text(json.dumps({
        "project": proj, "meta": meta, "engine_code_version": sess.code_version, "warmup": wu,
        "frame": frame, "seeds": seeds, "models": {m: strip(r) for m, r in results.items()},
        "a_vs_b": ab, "platform_twin": twins}, indent=2, default=str))
    (out_dir / "report.md").write_text(report(proj, sess, pf, wu, frame, seeds, results, ab, twins, today))
    log(f"done: {sess.runs} engine runs → {out_dir}/report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
