#!/usr/bin/env python3
"""Combine published nexus batteries at several outage START WEEKS into one
ranking — PLAN.md §27 WP 17.4 · §4 D317. Engine unchanged.

A nexus battery disrupts every supplier and supplied material alone at ONE
start week (`nexus_variant`). Whether a supplier is critical can depend on when
it fails, so a ranking the owner can act on is read across start weeks. This
script reads the batteries that are already published, refuses to combine any
that do not share one baseline, and writes one workbook.

What it combines, per target:
  * per start week, the battery's own Average (Δ lost sales in € vs the clean
    reference, CRN-paired over the replications) and its 95% half-width — the
    mean of the per-duration half-widths when a battery has several durations,
    which is never narrower than the half-width of their average;
  * the COMBINED score: the mean of the start weeks' Averages;
  * its half-width: the mean of the start weeks' half-widths. The batteries
    share their seeds, so the start weeks are correlated in a way the published
    aggregates cannot measure; the mean of the half-widths is the half-width of
    the average under PERFECT correlation — the widest it can be — so the
    interval stated is never too narrow;
  * a RANK RANGE and the probability of being in the top 10 (per kind), from a
    seeded Monte Carlo over each target's combined score drawn from N(mean, sd)
    with that same conservative sd. Targets are drawn independently; under the
    batteries' common random numbers they are positively correlated, which only
    makes true rank differences MORE certain than stated.

Nothing here runs the engine: a figure in the workbook is a published battery's
figure or a mean of them.

    python scripts/nexus/nexus_combine.py --project-name "Project TRON - version 2" \\
        --start-weeks 14,26,38,50 --seed 1 --replications 10 --durations 4 --out out/
"""
from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Optional

import numpy as np

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("nexus_job", HERE / "nexus_job.py")
nexus_job = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nexus_job)

#: Monte Carlo draws for the rank range, and their fixed seed (a rerun of the
#: combination on the same batteries gives the same workbook).
DRAWS = 4000
MC_SEED = 20261028
TOP_N = 10
#: The baseline fields every combined battery must share.
BINDING = ("model_validation_id", "policy_version_id", "dataset_version_id", "hash_inputs",
           "code_version", "seed", "replications", "durations", "warmup_week")


# ── reading ──────────────────────────────────────────────────────────────────

def read_batteries(project_name: str, start_weeks: list[int], seed: Optional[int],
                   replications: Optional[int], durations: Optional[list[int]],
                   model_code: Optional[str]) -> list[dict]:
    """The newest succeeded battery per requested start week that matches the
    filters. A start week with none is an error naming what was looked for."""
    sql, lit = nexus_job.sql, nexus_job.lit
    proj = sql(f"SELECT id FROM public.projects WHERE name = {lit(project_name)}")
    if len(proj) != 1:
        raise SystemExit(f"{len(proj)} projects are named {project_name!r}; name exactly one")
    pid = proj[0]["id"]
    model_filter = ""
    if model_code:
        mv = sql(f"SELECT id FROM public.model_validations WHERE project_id = '{pid}' "
                 f"AND model_code = {lit(model_code)}")
        if not mv:
            raise SystemExit(f"no Validated Model {model_code!r} on {project_name!r}")
        model_filter = f"AND params ->> 'model_validation_id' = '{mv[0]['id']}'"
    runs = sql(f"""SELECT r.id, r.code_version, r.finished_at, r.params, r.row_counts,
                          mv.name AS model_name, mv.model_code, mv.status AS model_status,
                          dv.version_no AS dataset_version_no, pv.version_no AS policy_version_no
                     FROM public.analysis_runs r
                     LEFT JOIN public.model_validations mv ON mv.id = (r.params ->> 'model_validation_id')::uuid
                     LEFT JOIN public.dataset_versions dv ON dv.id = r.dataset_version_id
                     LEFT JOIN public.policy_versions pv ON pv.id = (r.params ->> 'policy_version_id')::uuid
                    WHERE r.project_id = '{pid}' AND r.analysis_kind = 'nexus_stress'
                      AND r.status = 'succeeded' {model_filter}
                    ORDER BY r.finished_at DESC NULLS LAST""")
    picked: list[dict] = []
    for w in start_weeks:
        match = [r for r in map(_run_meta, runs) if r["requested_start_week"] == w
                 and (seed is None or r["seed"] == seed)
                 and (replications is None or r["replications"] == replications)
                 and (durations is None or r["durations"] == sorted(durations))]
        if not match:
            raise SystemExit(f"no published battery on {project_name!r} at start week {w} "
                             f"(seed {seed}, {replications} replications, durations {durations}) — "
                             "run it with nexus-stress.yml first")
        picked.append(match[0])
    for b in picked:
        b["rows"] = [{"entity_type": r["entity_type"], "entity_id": r["entity_id"],
                      "metrics": nexus_job._json(r["metrics"])}
                     for r in sql(f"SELECT entity_type, entity_id, metrics FROM public.analysis_results "
                                  f"WHERE run_id = '{b['run_id']}'")]
    return picked


def _run_meta(r: dict) -> dict:
    p = nexus_job._json(r["params"]) or {}
    rc = nexus_job._json(r["row_counts"]) or {}
    sc = p.get("scenario") or {}
    return {
        "run_id": r["id"], "finished_at": r["finished_at"], "code_version": r["code_version"],
        "model_validation_id": p.get("model_validation_id"), "policy_version_id": p.get("policy_version_id"),
        "dataset_version_id": p.get("dataset_version_id"), "hash_inputs": p.get("hash_inputs"),
        "model_name": r.get("model_name"), "model_code": r.get("model_code"),
        "model_status": r.get("model_status"),
        "dataset_version_no": r.get("dataset_version_no"), "policy_version_no": r.get("policy_version_no"),
        "requested_start_week": int(sc.get("start_week", 0)),
        "start_week": int(rc.get("start_week", sc.get("start_week", 0))),
        "durations": sorted(int(d) for d in sc.get("durations_weeks", [])),
        "seed": (p.get("run_settings") or {}).get("seed", rc.get("seed")),
        "replications": int(p.get("replications", rc.get("replications", 0)) or 0),
        "warmup_week": rc.get("warmup_week"), "window_weeks": rc.get("window_weeks"),
        "clean_lost_sales_eur": (rc.get("clean_lost_sales_eur") or {}).get("mean"),
    }


# ── combining (pure) ─────────────────────────────────────────────────────────

def check_same_baseline(batteries: list[dict]) -> None:
    """Refuse to average batteries that differ in anything but the start week."""
    if len({b["start_week"] for b in batteries}) != len(batteries):
        raise SystemExit("two batteries resolve to the same start week "
                         f"({[b['start_week'] for b in batteries]}): the warm-up moved a start")
    for k in BINDING:
        vals = {json.dumps(b.get(k), sort_keys=True) for b in batteries}
        if len(vals) > 1:
            raise SystemExit(f"the batteries differ in {k} ({sorted(vals)}) — only the start week may differ")


def start_week_value(metrics: dict) -> tuple[float, float]:
    """(Average €, 95% half-width) of one target in one battery."""
    bd = metrics.get("by_duration") or {}
    hws = [float(v.get("ci_halfwidth") or 0.0) for v in bd.values()]
    hw = float(np.mean(hws)) if hws else 0.0
    return float(metrics["average_eur"]), (hw if math.isfinite(hw) else 0.0)


def t_crit(n: int, level: float = 0.95) -> float:
    if n < 2:
        return float("inf")
    from scipy import stats as sps
    return float(sps.t.ppf(0.5 + level / 2.0, df=n - 1))


def combine(batteries: list[dict], draws: int = DRAWS, top_n: int = TOP_N, mc_seed: int = MC_SEED) -> dict:
    """{"material": [...], "supplier": [...]} — one row per target, ranked by the
    combined score within its kind, with the rank range and top-N probability."""
    weeks = [b["start_week"] for b in batteries]
    n = int(batteries[0]["replications"])
    tc = t_crit(n)
    per: dict[tuple[str, str], dict[int, tuple[float, float]]] = {}
    for b in batteries:
        for r in b["rows"]:
            per.setdefault((r["entity_type"], r["entity_id"]), {})[b["start_week"]] = start_week_value(r["metrics"])
    missing = [k for k, v in per.items() if len(v) != len(batteries)]
    if missing:
        raise SystemExit(f"{len(missing)} targets are missing from some batteries, e.g. {missing[:3]}")
    rng = np.random.default_rng(mc_seed)
    out: dict[str, list[dict]] = {}
    for kind in ("supplier", "material"):
        keys = sorted(k for k in per if k[0] == kind)
        if not keys:
            out[kind] = []
            continue
        means = np.array([[per[k][w][0] for w in weeks] for k in keys])
        hws = np.array([[per[k][w][1] for w in weeks] for k in keys])
        mean = means.mean(axis=1)
        hw = hws.mean(axis=1)
        sd = hw / tc if math.isfinite(tc) and tc > 0 else np.zeros_like(hw)
        # Rank within kind: score desc, then id — never arbitrary.
        order = sorted(range(len(keys)), key=lambda i: (-mean[i], keys[i][1]))
        rank = np.empty(len(keys), dtype=int)
        rank[order] = np.arange(1, len(keys) + 1)
        # Monte Carlo ranks (ties at 0 broken by id, as above).
        z = rng.standard_normal((draws, len(keys)))
        sim = mean[None, :] + z * sd[None, :]
        idx = np.argsort(-sim, axis=1, kind="stable")
        ranks = np.empty_like(idx)
        rows_ix = np.arange(draws)[:, None]
        ranks[rows_ix, idx] = np.arange(1, len(keys) + 1)[None, :]
        lo = np.percentile(ranks, 5, axis=0, method="lower")
        hi = np.percentile(ranks, 95, axis=0, method="higher")
        p_top = (ranks <= top_n).mean(axis=0)
        # Per start week: the rank WITHIN that week, to show timing dependence.
        week_rank = {}
        for j, w in enumerate(weeks):
            o = sorted(range(len(keys)), key=lambda i: (-means[i, j], keys[i][1]))
            wr = np.empty(len(keys), dtype=int)
            wr[o] = np.arange(1, len(keys) + 1)
            week_rank[w] = wr
        rows = []
        for i in order:
            lost = bool(mean[i] > 0.5 or hw[i] > 0.5)
            rows.append({
                "rank": int(rank[i]), "id": keys[i][1], "kind": kind,
                "combined_eur": round(float(mean[i]), 2), "ci_halfwidth_eur": round(float(hw[i]), 2),
                "rank_low": int(lo[i]) if lost else None, "rank_high": int(hi[i]) if lost else None,
                "p_top": round(float(p_top[i]), 3) if lost else 0.0,
                "weeks_in_top": int(sum(week_rank[w][i] <= top_n for w in weeks)) if lost else 0,
                "by_week": {w: {"eur": round(float(means[i, j]), 2), "ci_halfwidth_eur": round(float(hws[i, j]), 2),
                                "rank": int(week_rank[w][i])} for j, w in enumerate(weeks)},
                "no_loss": not lost,
            })
        out[kind] = rows
    return out


def reliability(row: dict, top_n: int = TOP_N) -> str:
    """One word for the rank, from its range and top-N probability."""
    if row["no_loss"]:
        return "no loss"
    if row["rank_high"] is not None and row["rank_high"] <= top_n and row["p_top"] >= 0.95:
        return "solid top"
    if row["p_top"] >= 0.5:
        return "likely top"
    if row["p_top"] > 0.05:
        return "borderline"
    return "not top"


# ── writing ──────────────────────────────────────────────────────────────────

def write_outputs(batteries: list[dict], combined: dict, project_name: str, out_dir: Path) -> dict:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    out_dir.mkdir(parents=True, exist_ok=True)
    weeks = [b["start_week"] for b in batteries]
    b0 = batteries[0]
    wb = Workbook()
    head = Font(bold=True, color="FFFFFF")
    fill = PatternFill("solid", fgColor="18181B")
    tone = {"solid top": "D1FAE5", "likely top": "ECFCCB", "borderline": "FEF3C7"}

    def sheet(title: str, rows: list[dict]):
        ws = wb.create_sheet(title)
        cols = (["Rank", title[:-1] if title.endswith("s") else title, "Combined lost sales (€)", "± 95% (€)",
                 "Rank range (90%)", f"P(top {TOP_N})", "Reading", f"Start weeks in top {TOP_N}"]
                + [f"Week {w} (€)" for w in weeks] + [f"Week {w} rank" for w in weeks])
        ws.append(cols)
        for r in rows:
            rr = "—" if r["rank_low"] is None else (f"{r['rank_low']}" if r["rank_low"] == r["rank_high"]
                                                   else f"{r['rank_low']}–{r['rank_high']}")
            word = reliability(r)
            ws.append([r["rank"], r["id"], r["combined_eur"], r["ci_halfwidth_eur"], rr, r["p_top"], word,
                       f"{r['weeks_in_top']} of {len(weeks)}"]
                      + [r["by_week"][w]["eur"] for w in weeks] + [r["by_week"][w]["rank"] for w in weeks])
            if word in tone:
                for c in ws[ws.max_row][:7]:
                    c.fill = PatternFill("solid", fgColor=tone[word])
        for c in ws[1]:
            c.font, c.fill, c.alignment = head, fill, Alignment(wrap_text=True, vertical="center")
        for i, _ in enumerate(cols, start=1):
            ws.column_dimensions[get_column_letter(i)].width = 14 if i > 2 else (7 if i == 1 else 12)
        for row in ws.iter_rows(min_row=2):
            for c in row[2:4] + row[8:8 + len(weeks)]:
                c.number_format = "#,##0"
            row[5].number_format = "0%"
        ws.freeze_panes = "C2"

    wb.remove(wb.active)
    sheet("Suppliers", combined["supplier"])
    sheet("Materials", combined["material"])

    ws = wb.create_sheet("How it was made")
    info = [
        ("Project", project_name),
        ("Validated Model", f"{b0.get('model_name')} ({b0.get('model_code')})"),
        ("Data version", f"v{b0.get('dataset_version_no')}  ({b0['dataset_version_id']})"),
        ("Policy version", f"v{b0.get('policy_version_no')}  ({b0['policy_version_id']})"),
        ("Engine", b0["code_version"]),
        ("Seed", b0["seed"]),
        ("Replications per battery", b0["replications"]),
        ("Outage", f"full outage, {', '.join(str(d) for d in b0['durations'])} week(s)"),
        ("Warm-up week", b0["warmup_week"]),
        ("KPI window (weeks)", b0["window_weeks"]),
        ("Start weeks combined", ", ".join(str(w) for w in weeks)),
        ("Combined", dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")),
        ("", ""),
        ("Battery run ids", ""),
    ] + [(f"  week {b['start_week']}", f"{b['run_id']}  (finished {b['finished_at']}, "
                                       f"clean reference lost sales €{(b['clean_lost_sales_eur'] or 0):,.0f})")
         for b in batteries] + [
        ("", ""),
        ("Method", ""),
        ("  Score", "Mean over start weeks of each battery's Average: Δ lost sales in € over the KPI window, "
                    "outage run minus the same run without it, paired on the same seeds."),
        ("  ± 95%", "Mean of the start weeks' half-widths — the widest the interval of the average can be "
                    "whatever the correlation between start weeks, so never too narrow."),
        ("  Rank range", f"5th–95th percentile of the target's rank within its kind over {DRAWS} Monte Carlo "
                         f"draws of every target's score from N(score, sd); seed {MC_SEED}."),
        (f"  P(top {TOP_N})", f"Share of those draws in which the target ranks in the top {TOP_N} of its kind."),
        ("  Reading", f"solid top: rank range inside the top {TOP_N} and P ≥ 95%; likely top: P ≥ 50%; "
                      "borderline: P > 5%; not top: otherwise; no loss: no lost sales at any start week."),
        ("  Engine", "Unchanged. Every figure is a published battery's figure or a mean of them."),
    ]
    for k, v in info:
        ws.append([k, v])
    ws.column_dimensions["A"].width = 26
    ws.column_dimensions["B"].width = 120
    for c in ws["A"]:
        c.font = Font(bold=True)

    slug = re.sub(r"[^a-z0-9]+", "-", project_name.lower()).strip("-")
    stem = f"nexus-combined-{slug}-weeks-{'-'.join(str(w) for w in weeks)}-seed{b0['seed']}-{b0['replications']}reps"
    xlsx = out_dir / f"{stem}.xlsx"
    wb.save(xlsx)
    (out_dir / f"{stem}.json").write_text(json.dumps(
        {"project": project_name, "start_weeks": weeks,
         "batteries": [{k: v for k, v in b.items() if k != "rows"} for b in batteries],
         "combined": combined}, indent=1, default=str))
    return {"xlsx": xlsx, "stem": stem}


def report(batteries: list[dict], combined: dict, project_name: str, files: dict) -> str:
    weeks = [b["start_week"] for b in batteries]
    b0 = batteries[0]
    eur = lambda x: f"€{x:,.0f}"
    lines = [f"## Nexus — combined over start weeks {', '.join(map(str, weeks))} — {project_name}", "",
             f"- Model {b0.get('model_code')} · data v{b0.get('dataset_version_no')} · policies "
             f"v{b0.get('policy_version_no')} · engine `{b0['code_version']}`",
             f"- {b0['replications']} replications on seed {b0['seed']} per start week · outage "
             f"{', '.join(map(str, b0['durations']))} week(s) · file `{files['xlsx'].name}`", ""]
    for kind in ("supplier", "material"):
        lines += [f"### Top 15 {kind}s", "",
                  "| # | id | combined | ± 95% | rank range | P(top 10) | reading | "
                  + " | ".join(f"wk {w}" for w in weeks) + " |",
                  "|---|---|---|---|---|---|---|" + "---|" * len(weeks)]
        for r in combined[kind][:15]:
            rr = "—" if r["rank_low"] is None else f"{r['rank_low']}–{r['rank_high']}"
            lines.append(f"| {r['rank']} | {r['id']} | {eur(r['combined_eur'])} | {eur(r['ci_halfwidth_eur'])} | "
                         f"{rr} | {r['p_top']:.0%} | {reliability(r)} | "
                         + " | ".join(f"{eur(r['by_week'][w]['eur'])} (#{r['by_week'][w]['rank']})" for w in weeks)
                         + " |")
        lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--project-name", required=True)
    ap.add_argument("--start-weeks", required=True, help="e.g. 14,26,38,50")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--replications", type=int)
    ap.add_argument("--durations", help='"4", "2,4" or "2-9"')
    ap.add_argument("--model-code")
    ap.add_argument("--out", required=True)
    ap.add_argument("--summary-md")
    a = ap.parse_args(argv)
    weeks = [int(w) for w in a.start_weeks.replace(" ", "").split(",") if w]
    if len(weeks) < 2:
        ap.error("name at least two start weeks")
    batteries = read_batteries(a.project_name, weeks, a.seed, a.replications,
                               nexus_job.parse_durations(a.durations), a.model_code)
    check_same_baseline(batteries)
    batteries.sort(key=lambda b: b["start_week"])
    combined = combine(batteries)
    files = write_outputs(batteries, combined, a.project_name, Path(a.out))
    md = report(batteries, combined, a.project_name, files)
    print(md)
    if a.summary_md:
        Path(a.summary_md).write_text(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
