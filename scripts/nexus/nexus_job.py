#!/usr/bin/env python3
"""The nexus battery job — PLAN.md §27 WP 17.4 (§4 D310).

Three steps, one per job of `.github/workflows/nexus-stress.yml`:

    prepare  resolve the project, its ACTIVE Validated Model and the data version;
             read the two frozen snapshots; run the clean reference once (warm-up
             and digest); open the battery (`analysis_start_nexus_stress`); split
             the targets into shards; write ONE bundle every shard reads.
    shard    rebuild the same scenario from the bundle, prove the clean reference
             is the bundle's (warm-up and digest), run its targets, write its rows.
             Never talks to the database.
    publish  merge every shard's rows (each target exactly once), rank them as one
             battery and publish it whole (`analysis_publish_nexus_stress`).
    fail     mark the run failed (`analysis_fail_run`) so its key is free again.

The database is reached through the Supabase Management API's SQL endpoint, the
`seed-project.yml` route, with `SUPABASE_ACCESS_TOKEN` and the project ref read
from `src/integrations/supabase/client.ts`. `--local-dataset` / `--local-policy`
run `prepare` against files instead (tests, and a dry run on the Example project).

The engine is whatever is installed — the workflow installs the committed wheels
(`public/engine/*.whl`), so the battery binds the build a platform run binds.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import secrets
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "sim-worker"))

#: Default replications per cell. Every cell is paired against the clean run on
#: the same seeds, which is what makes ten enough to rank; stated on the card.
DEFAULT_REPLICATIONS = 10
#: Target wall time of one shard, and the most shards a run may ask for
#: (GitHub caps concurrent jobs per plan — the rest would only queue).
SHARD_TARGET_SECONDS = 45 * 60
MAX_SHARDS = 20


# ── the database (Management API SQL) ────────────────────────────────────────

def _project_ref() -> str:
    src = (ROOT / "src" / "integrations" / "supabase" / "client.ts").read_text()
    m = re.search(r'SUPABASE_URL = "https://([^.]+)\.', src)
    if not m:
        raise SystemExit("could not read the project ref from src/integrations/supabase/client.ts")
    return m.group(1)


def sql(query: str) -> list[dict]:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        raise SystemExit("SUPABASE_ACCESS_TOKEN is not set")
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{_project_ref()}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read() or b"[]")
    except urllib.error.HTTPError as e:  # the database's own message is the useful part
        raise SystemExit(f"SQL failed ({e.code}): {e.read().decode(errors='replace')[:2000]}")


def lit(value: Any) -> str:
    """A SQL literal for a JSON value or a string — dollar-quoted with a tag the
    value cannot contain, so no escaping can go wrong."""
    text = value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))
    tag = "nx" + secrets.token_hex(6)
    while f"${tag}$" in text:
        tag = "nx" + secrets.token_hex(6)
    return f"${tag}${text}${tag}$"


def uuid_or_null(v: Optional[str]) -> str:
    if not v:
        return "NULL"
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", v):
        raise SystemExit(f"not a uuid: {v!r}")
    return f"'{v}'::uuid"


# ── reading the baseline ─────────────────────────────────────────────────────

def read_baseline(project_name: str, model_id: Optional[str], dataset_version_id: Optional[str],
                  actor_email: Optional[str], model_code: Optional[str] = None) -> dict:
    rows = sql(f"SELECT id, supply_chain_model, modeler_id FROM public.projects WHERE name = {lit(project_name)}")
    if len(rows) != 1:
        raise SystemExit(f"{len(rows)} projects are named {project_name!r}; name exactly one")
    project = rows[0]
    pid = project["id"]
    # A model is named by its id, or by the code the Lab shows ("2026Q4-4"), or
    # defaults to the project's active one. A named model must still be active.
    model_filter = (f"id = {uuid_or_null(model_id)}" if model_id else
                    f"model_code = {lit(model_code)}" if model_code else
                    "status = 'active' AND revoked_at IS NULL")
    models = sql(f"""SELECT id, name, model_code, status, revoked_at, policy_version_id, dataset_version_id,
                            protocol, adopted_warmup_days, warmup_method
                       FROM public.model_validations
                      WHERE project_id = '{pid}' AND {model_filter}
                      ORDER BY validated_at DESC NULLS LAST, created_at DESC LIMIT 1""")
    if not models and (model_id or model_code):
        raise SystemExit(f"{project_name!r} has no Validated Model {model_id or model_code!r}")
    if not models:
        raise SystemExit(f"{project_name!r} has no active Validated Model — validate a baseline first "
                         "(PLAN.md §27 WP 17.7: the battery runs only on one)")
    model = models[0]
    if model["status"] != "active" or model["revoked_at"]:
        raise SystemExit(f"Validated Model {model['id']} is {model['status']}; a battery runs only on an active one")
    dsv = dataset_version_id or model["dataset_version_id"]
    ds = sql(f"SELECT id, version_no, snapshot FROM public.dataset_versions "
             f"WHERE id = {uuid_or_null(dsv)} AND project_id = '{pid}'")
    pv = sql(f"SELECT id, version_no, snapshot FROM public.policy_versions "
             f"WHERE id = {uuid_or_null(model['policy_version_id'])}")
    if not ds or not pv:
        raise SystemExit("the model's data version or policy version could not be read")
    actor = project["modeler_id"]
    if actor_email:
        who = sql(f"SELECT id FROM public.approved_users WHERE lower(email) = lower({lit(actor_email)})")
        if not who:
            raise SystemExit(f"no approved user {actor_email!r}")
        actor = who[0]["id"]
    return {"project_id": pid, "project_name": project_name,
            "project_model": project["supply_chain_model"], "actor_user_id": actor,
            "model": {k: model[k] for k in ("id", "name", "model_code", "protocol",
                                            "adopted_warmup_days", "warmup_method")},
            "dataset_version": {"id": ds[0]["id"], "version_no": ds[0]["version_no"]},
            "policy_version": {"id": pv[0]["id"], "version_no": pv[0]["version_no"]},
            "dataset": _json(ds[0]["snapshot"]), "policy_snapshot": _json(pv[0]["snapshot"])}


def _json(v: Any) -> Any:
    return json.loads(v) if isinstance(v, str) else v


def scenario_from_model(model: dict, replications: int, seed: Optional[int] = None) -> dict:
    """The battery's run settings, from the Validated Model's own protocol: its
    horizon, seed, CRN, confidence level and ADOPTED warm-up (manual, so every
    shard and every rerun uses the same one). Replications are the battery's,
    and so is the seed when one is given (it is recorded on the run either way).

    Replication k draws from (seed, k) alone, so a battery with N replications
    contains a battery with fewer EXACTLY: run 1 now and 10 later on the same
    seed, and the first replication of the second is the first run."""
    p = _json(model.get("protocol")) or {}
    ci = p.get("ci_level", 0.95)
    sc = {
        "name": "nexus battery",
        "horizon_days": int(p.get("horizon_weeks", 156)) * 7,
        "seed": int(seed) if seed is not None else int(p.get("root_seed", 42)),
        "crn": bool(p.get("crn", True)),
        "ci_level": int(round(ci * 100)) if ci <= 1 else int(ci),
        "replications": int(replications),
        "disruption_schedule": [],
    }
    if model.get("adopted_warmup_days") is not None:
        sc.update(warmup_mode="manual", warmup_days=int(model["adopted_warmup_days"]))
    return sc


# ── the engine side ──────────────────────────────────────────────────────────

def mapped_scenario(bundle: dict):
    from scsim.io import from_project_data
    from sim_worker.local import project_data_from_snapshots

    data = project_data_from_snapshots(bundle["dataset"], bundle["policy_snapshot"],
                                       bundle["scenario"], bundle.get("project_model"))
    return from_project_data(data)


def shard_targets(targets: list, n: int) -> list[list]:
    """Round-robin by position, so every shard gets a mix of suppliers and materials."""
    return [targets[i::n] for i in range(n)]


def prepare(args) -> dict:
    from scsim.stress.nexus import all_targets, nexus_scenario_hash, nexus_variant, run_nexus_battery
    from sim_worker.build import code_version

    if args.local_dataset:
        base = {"project_id": None, "project_name": args.project_name or "local",
                "project_model": args.project_model, "actor_user_id": None,
                "model": {"id": None, "name": "local", "protocol": {}, "adopted_warmup_days": None},
                "dataset_version": {"id": None}, "policy_version": {"id": None},
                "dataset": json.loads(Path(args.local_dataset).read_text()),
                "policy_snapshot": json.loads(Path(args.local_policy).read_text()) if args.local_policy else {}}
    else:
        base = read_baseline(args.project_name, args.model_id, args.dataset_version_id, args.actor_email,
                             args.model_code)
    bundle = {**base, "scenario": scenario_from_model(base["model"], args.replications, args.seed)}
    spec = nexus_variant(args.start_week, parse_durations(args.durations))
    if args.horizon_days:
        bundle["scenario"]["horizon_days"] = int(args.horizon_days)

    mapping = mapped_scenario(bundle)
    scen = mapping.scenario
    t0 = time.perf_counter()
    clean = run_nexus_battery(scen, targets=[], spec=spec)   # the clean reference alone
    t_clean = time.perf_counter() - t0
    targets = [{"kind": t.kind, "id": t.id} for t in all_targets(scen)]
    cells = len(targets) * len(spec["durations_weeks"])
    est = cells * max(t_clean, 0.05) * 1.5
    n = int(args.shards) if args.shards else max(1, min(MAX_SHARDS, math.ceil(est / SHARD_TARGET_SECONDS)))
    n = min(n, max(1, len(targets)))
    bundle.update({
        "code_version": code_version(),
        "nexus_scenario": spec, "scenario_hash": nexus_scenario_hash(spec),
        "warmup_week": clean.warmup_week, "start_week": clean.start_week,
        "clean_digest": clean.clean_digest,
        "shards": shard_targets(targets, n),
        "budget": {"targets": len(targets), "cells": cells, "clean_seconds": round(t_clean, 2),
                   "estimated_cpu_seconds": round(est), "shards": n},
        "mapping_warnings": mapping.warning_dicts[:200],
    })
    if not args.local_dataset:
        params = {"scenario": spec, "scenario_hash": nexus_scenario_hash(spec),
                  "replications": int(args.replications), "run_settings": bundle["scenario"]}
        res = sql(f"""SELECT public.analysis_start_nexus_stress(
                        '{bundle['project_id']}'::uuid, {uuid_or_null(bundle['model']['id'])},
                        {uuid_or_null(bundle['dataset_version']['id'])}, {lit(bundle['code_version'])},
                        {lit(params)}::jsonb, '{bundle['actor_user_id']}'::uuid) AS r""")
        bundle["run"] = _json(res[0]["r"])
    return bundle


def shard(bundle: dict, index: int) -> dict:
    from scsim.stress.nexus import NexusTarget, run_nexus_battery

    scen = mapped_scenario(bundle).scenario
    targets = [NexusTarget(t["kind"], t["id"]) for t in bundle["shards"][index]]
    t0 = time.perf_counter()
    b = run_nexus_battery(scen, targets=targets, expected_warmup=bundle["warmup_week"],
                          expected_clean_digest=bundle["clean_digest"], spec=bundle["nexus_scenario"])
    return {"index": index, "seconds": round(time.perf_counter() - t0, 1),
            "summary": b.summary(), "results": b.results()}


def merge(bundle: dict, shard_outputs: list[dict]) -> tuple[list[dict], dict]:
    from scsim.stress.nexus import merge_shards

    got = sorted(o["index"] for o in shard_outputs)
    if got != list(range(len(bundle["shards"]))):
        raise SystemExit(f"shards {got} came back; the battery has {len(bundle['shards'])}")
    results = merge_shards([o["results"] for o in shard_outputs], bundle["nexus_scenario"])
    expected = {(t["kind"], t["id"]) for s in bundle["shards"] for t in s}
    if {(r["entity_type"], r["entity_id"]) for r in results} != expected:
        raise SystemExit("the merged rows are not the battery's targets")
    s0 = shard_outputs[0]["summary"]
    summary = {**s0, "targets": len(results),
               "materials": sum(r["entity_type"] == "material" for r in results),
               "suppliers": sum(r["entity_type"] == "supplier" for r in results),
               "shards": len(shard_outputs),
               "shard_seconds": [o["seconds"] for o in sorted(shard_outputs, key=lambda o: o["index"])],
               "code_version": bundle["code_version"]}
    return results, summary


def report(bundle: dict, results: list[dict], summary: dict) -> str:
    """Markdown for the job summary — the reading WP 17.4's §16 entry quotes."""
    eur = lambda x: f"€{x:,.0f}"
    ds = [str(d) for d in bundle["nexus_scenario"]["durations_weeks"]]
    span = f"{ds[0]}–{ds[-1]} weeks" if len(ds) > 1 else f"{ds[0]} weeks"
    lines = [f"## Nexus battery — {bundle['project_name']}", "",
             f"- Validated Model: **{bundle['model'].get('name')}** ({bundle['model'].get('model_code') or bundle['model']['id']})",
             f"- Data version: v{bundle['dataset_version'].get('version_no')} · policy version: v{bundle['policy_version'].get('version_no')}",
             f"- Engine: `{bundle['code_version']}`",
             f"- Warm-up week {summary['warmup_week']} → outage from week {summary['start_week']}, {span}, "
             f"{summary['replications']} replication(s) on seed {bundle['scenario']['seed']}, "
             f"KPI window {summary['window_weeks']} weeks",
             f"- Clean reference: lost sales {eur(summary['clean_lost_sales_eur']['mean'] or 0)}",
             f"- {summary['materials']} materials, {summary['suppliers']} suppliers, {summary['shards']} shard(s), "
             f"shard seconds {summary['shard_seconds']}", ""]
    for kind in ("material", "supplier"):
        rows = [r for r in results if r["entity_type"] == kind][:10]
        cols = sorted({ds[0], ds[len(ds) // 2], ds[-1]}, key=int)
        lines += [f"### Top {len(rows)} {kind}s by Average", "",
                  "| # | id | " + " | ".join(f"{d} wk" for d in cols) + " | Average |",
                  "|---|---|" + "---|" * len(cols) + "---|"]
        for r in rows:
            m = r["metrics"]; bd = m["by_duration"]
            lines.append(f"| {m['rank']} | {r['entity_id']} | "
                         + " | ".join(eur(bd[d]['mean']) for d in cols) + f" | {eur(m['average_eur'])} |")
        lines.append("")
    return "\n".join(lines)


def parse_durations(text: Optional[str]) -> Optional[list[int]]:
    """"5" or "2,3,4" or "2-9" → weeks; blank → the shared scenario's."""
    if not text or not str(text).strip():
        return None
    out: list[int] = []
    for part in str(text).replace(" ", "").split(","):
        if "-" in part:
            lo, hi = part.split("-", 1)
            out += list(range(int(lo), int(hi) + 1))
        elif part:
            out.append(int(part))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--project-name")
    p.add_argument("--model-id")
    p.add_argument("--model-code", help='the code the Lab shows, e.g. "2026Q4-4"')
    p.add_argument("--seed", type=int, help="root seed (default: the model protocol's)")
    p.add_argument("--start-week", type=int, help="outage start week (default: the shared scenario's, 26)")
    p.add_argument("--durations", help='outage durations in weeks: "5", "2,4" or "2-9" (default 2-9)')
    p.add_argument("--dataset-version-id")
    p.add_argument("--actor-email")
    p.add_argument("--replications", type=int, default=DEFAULT_REPLICATIONS)
    p.add_argument("--horizon-days", type=int)
    p.add_argument("--shards", type=int)
    p.add_argument("--local-dataset")
    p.add_argument("--local-policy")
    p.add_argument("--project-model")
    p.add_argument("--out", required=True)
    s = sub.add_parser("shard")
    s.add_argument("--bundle", required=True)
    s.add_argument("--index", type=int, required=True)
    s.add_argument("--out", required=True)
    u = sub.add_parser("publish")
    u.add_argument("--bundle", required=True)
    u.add_argument("--rows-dir", required=True)
    u.add_argument("--dry-run", action="store_true")
    u.add_argument("--summary-md")
    f = sub.add_parser("fail")
    f.add_argument("--bundle", required=True)
    f.add_argument("--reason", required=True)
    a = ap.parse_args(argv)

    if a.cmd == "prepare":
        if not a.local_dataset and not a.project_name:
            ap.error("prepare needs --project-name (or --local-dataset)")
        bundle = prepare(a)
        Path(a.out).write_text(json.dumps(bundle))
        run = bundle.get("run") or {}
        print(json.dumps({"budget": bundle["budget"], "warmup_week": bundle["warmup_week"],
                          "start_week": bundle["start_week"], "code_version": bundle["code_version"],
                          "run": {k: run.get(k) for k in ("run_id", "cache_hit", "status", "claimed_by_other")}}))
        if "GITHUB_OUTPUT" in os.environ:
            skip = bool(run.get("cache_hit") or run.get("claimed_by_other"))
            with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
                fh.write(f"shards={json.dumps(list(range(len(bundle['shards']))))}\n")
                fh.write(f"skip={'true' if skip else 'false'}\n")
        return 0
    bundle = json.loads(Path(a.bundle).read_text())
    if a.cmd == "shard":
        out = shard(bundle, a.index)
        Path(a.out).write_text(json.dumps(out))
        print(f"shard {a.index}: {len(out['results'])} targets in {out['seconds']} s")
        return 0
    if a.cmd == "publish":
        outs = [json.loads(p.read_text()) for p in sorted(Path(a.rows_dir).rglob("shard-*.json"))]
        results, summary = merge(bundle, outs)
        md = report(bundle, results, summary)
        print(md)
        if a.summary_md:
            Path(a.summary_md).write_text(md)
        if a.dry_run or not (bundle.get("run") or {}).get("run_id"):
            return 0
        res = sql(f"""SELECT public.analysis_publish_nexus_stress(
                        '{bundle['run']['run_id']}'::uuid, {lit(results)}::jsonb, {lit(summary)}::jsonb,
                        '{bundle['actor_user_id']}'::uuid) AS r""")
        print(json.dumps(_json(res[0]["r"])))
        return 0
    if a.cmd == "fail":
        run_id = (bundle.get("run") or {}).get("run_id")
        if run_id and not (bundle["run"].get("cache_hit") or bundle["run"].get("claimed_by_other")):
            sql(f"""SELECT public.analysis_fail_run('{run_id}'::uuid,
                      {lit([{"reason": a.reason}])}::jsonb, '{bundle['actor_user_id']}'::uuid)""")
            print(f"run {run_id} marked failed: {a.reason}")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
