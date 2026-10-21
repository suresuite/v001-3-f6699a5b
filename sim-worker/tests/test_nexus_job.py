"""The nexus battery job (PLAN.md §27 WP 17.4) — everything it does short of the database.

`scripts/nexus/nexus_job.py` is three CI jobs; this runs them end to end on the
Example project from files (`--local-dataset`), and pins the pieces the database
half depends on: the run settings come from the Validated Model's protocol, the
SQL literals cannot be broken out of, and a merged battery is the unsharded one.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("nexus_job", ROOT / "scripts" / "nexus" / "nexus_job.py")
nexus_job = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nexus_job)

DATASET = ROOT / "scripts" / "example_project" / "dataset.json"


def test_run_settings_come_from_the_models_protocol():
    sc = nexus_job.scenario_from_model(
        {"protocol": {"horizon_weeks": 104, "root_seed": 7, "crn": True, "ci_level": 0.95},
         "adopted_warmup_days": 91}, replications=12)
    assert sc["horizon_days"] == 728 and sc["seed"] == 7 and sc["ci_level"] == 95
    assert sc["replications"] == 12 and sc["disruption_schedule"] == []
    # The model's ADOPTED warm-up, manual — every shard and rerun uses the same one.
    assert (sc["warmup_mode"], sc["warmup_days"]) == ("manual", 91)


def test_sql_literals_are_dollar_quoted_with_a_tag_the_value_lacks():
    nasty = "'; DROP TABLE x; -- $nx$ $$"
    out = nexus_job.lit(nasty)
    tag = out[: out.index("$", 1) + 1]
    assert out == f"{tag}{nasty}{tag}" and tag not in nasty
    js = nexus_job.lit({"a": "b"})
    jtag = js[: js.index("$", 1) + 1]
    assert js == f'{jtag}{{"a":"b"}}{jtag}'
    with pytest.raises(SystemExit):
        nexus_job.uuid_or_null("1 OR 1=1")


def test_shards_mix_kinds_and_cover_every_target_once():
    targets = [{"kind": "supplier", "id": f"S{i}"} for i in range(3)] + \
              [{"kind": "material", "id": f"M{i}"} for i in range(4)]
    shards = nexus_job.shard_targets(targets, 3)
    assert sorted(t["id"] for s in shards for t in s) == sorted(t["id"] for t in targets)
    assert all(s for s in shards)


@pytest.fixture(scope="module")
def local_run(tmp_path_factory):
    d = tmp_path_factory.mktemp("nexus")
    assert nexus_job.main(["prepare", "--local-dataset", str(DATASET), "--horizon-days", "728",
                           "--shards", "2", "--replications", "4", "--out", str(d / "bundle.json")]) == 0
    for i in (0, 1):
        assert nexus_job.main(["shard", "--bundle", str(d / "bundle.json"), "--index", str(i),
                               "--out", str(d / f"shard-{i}.json")]) == 0
    return d


def test_the_job_end_to_end_equals_one_unsharded_battery(local_run):
    from scsim.stress.nexus import run_nexus_battery

    bundle = json.loads((local_run / "bundle.json").read_text())
    outs = [json.loads((local_run / f"shard-{i}.json").read_text()) for i in (0, 1)]
    results, summary = nexus_job.merge(bundle, outs)
    whole = run_nexus_battery(nexus_job.mapped_scenario(bundle).scenario)
    assert results == whole.results()
    assert summary["targets"] == 5 and summary["shards"] == 2
    assert summary["start_week"] == bundle["start_week"]
    md = nexus_job.report(bundle, results, summary)
    assert "Top 2 materials" in md and "Top 3 suppliers" in md


def test_publish_refuses_a_missing_or_doubled_shard(local_run):
    bundle = json.loads((local_run / "bundle.json").read_text())
    one = json.loads((local_run / "shard-0.json").read_text())
    with pytest.raises(SystemExit, match="came back"):
        nexus_job.merge(bundle, [one])
    with pytest.raises(SystemExit):
        nexus_job.merge(bundle, [one, one])
