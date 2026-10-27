# SCSIM — supply chain simulation library and stress-test framework.
# Copyright (c) 2023-2026 Phu Nguyen. All rights reserved until the open-access
# release; see scsim/NOTICE.md for licensing, funding and citation.
# Developed in part within the ACCURATE project (Horizon Europe, GA 101138269).

"""The nexus battery (PLAN.md §27 WP 17.2, §4 D310).

The network, hand-worked: one product needs m1 and m2. m1 is sole-sourced
from s1; m2 comes from s2 (primary) and s3 (backup). Material cover is held
at three weeks so a 2–9-week outage shows (measured: a 2-week outage is
absorbed, a 9-week one loses six weeks of sales). So:

* s1 is the sole source of a required material — its outage stops the product;
* s2's outage is covered by s3 when the backup-supplier policy is on;
* a MATERIAL outage stops every source of it, so m1 and m2 both stop the product.
"""
from __future__ import annotations

import pytest

from scsim import BomLine, Material, Network, Product, Scenario, Supplier, SupplierLink
from scsim.entities.enums import DemandModel
from scsim.stress.nexus import (
    NEXUS_SCENARIO,
    NexusBatteryError,
    NexusTarget,
    all_targets,
    merge_shards,
    nexus_scenario_hash,
    nexus_variant,
    run_nexus_battery,
    start_week_for,
)

from .conftest import make_settings

THIN = {"inventory_control": {"coverage_weeks": {"nominal": 3, "alert": 3, "crisis": 3}}}
BACKUP = {**THIN, "backup_supplier": {"cooldown_weeks": 0}}


def network() -> Network:
    return Network(
        suppliers=[Supplier(id="s1"), Supplier(id="s2"), Supplier(id="s3")],
        materials=[Material(id="m1", cost=2.0), Material(id="m2", cost=2.0)],
        products=[Product(id="p1", unit_price=10.0, demand_mode=100.0,
                          demand_model=DemandModel.DETERMINISTIC, production_capacity=200.0)],
        bom=[BomLine(product_id="p1", material_id="m1", rate=1.0),
             BomLine(product_id="p1", material_id="m2", rate=1.0)],
        supplier_links=[
            SupplierLink(supplier_id="s1", material_id="m1", cost=2.0, lead_time_weeks=2),
            SupplierLink(supplier_id="s2", material_id="m2", cost=2.0, lead_time_weeks=2),
            SupplierLink(supplier_id="s3", material_id="m2", cost=2.4, lead_time_weeks=2),
        ],
    )


def scenario(policies=None, **kw) -> Scenario:
    return Scenario(name="nexus", network=network(), settings=make_settings(**kw),
                    events=[], policies=policies if policies is not None else THIN)


def by_id(battery):
    return {(r.target.kind, r.target.id): r for r in battery.rows}


@pytest.fixture(scope="module")
def battery():
    return run_nexus_battery(scenario(BACKUP))


def test_targets_are_suppliers_and_materials_only():
    kinds = {t.kind for t in all_targets(scenario())}
    assert kinds == {"supplier", "material"}
    with pytest.raises(NexusBatteryError, match="not a supplier or supplied material"):
        run_nexus_battery(scenario(), targets=[NexusTarget("material", "p1")])


def test_every_duration_is_a_column_and_average_is_their_mean(battery):
    for r in battery.rows:
        assert sorted(r.by_duration) == NEXUS_SCENARIO["durations_weeks"]
        means = [r.by_duration[d]["mean"] for d in NEXUS_SCENARIO["durations_weeks"]]
        assert r.average_eur == pytest.approx(sum(means) / len(means))


def test_loss_grows_with_the_outage(battery):
    s1 = by_id(battery)[("supplier", "s1")]
    means = [s1.by_duration[d]["mean"] for d in NEXUS_SCENARIO["durations_weeks"]]
    assert means == sorted(means) and means[-1] > 0.0
    # The fill-rate drop is the same story in service terms: none at 2 weeks, some at 9.
    assert s1.fill_rate_drop_by_duration[2] == 0.0 < s1.fill_rate_drop_by_duration[9]


def test_sole_source_outranks_a_covered_supplier_and_the_policy_counts(battery):
    rows = by_id(battery)
    s1, s2 = rows[("supplier", "s1")], rows[("supplier", "s2")]
    assert s1.average_eur > s2.average_eur == 0.0
    assert s1.rank < s2.rank
    # Without the backup policy the same s2 outage costs more: rule 3, policies run.
    no_backup = by_id(run_nexus_battery(scenario(THIN), targets=[NexusTarget("supplier", "s2")]))
    assert no_backup[("supplier", "s2")].average_eur > s2.average_eur


def test_a_material_outage_stops_every_source(battery):
    rows = by_id(battery)
    # m2 is dual-sourced, but a material outage stops both sources — it costs as
    # much as m1's, more than its covered primary supplier's.
    assert rows[("material", "m2")].average_eur == pytest.approx(rows[("material", "m1")].average_eur)
    assert rows[("material", "m2")].average_eur > rows[("supplier", "s2")].average_eur


def test_order_is_average_then_nine_weeks_then_kind_then_id(battery):
    ranked = [(r.target.kind, r.target.id) for r in battery.rows]
    assert [r.rank for r in battery.rows] == list(range(1, len(ranked) + 1))
    # m1, m2 and s1 all stop the product for the same weeks: an exact tie, broken
    # by kind ("material" < "supplier") and then id.
    assert ranked[:3] == [("material", "m1"), ("material", "m2"), ("supplier", "s1")]


def test_start_week_rule_both_branches():
    assert start_week_for(10) == 26          # warm-up ends before week 26
    assert start_week_for(30) == 31          # warm-up ends later: warm-up + 1
    early = run_nexus_battery(scenario(), targets=[NexusTarget("supplier", "s1")])
    assert (early.warmup_week, early.start_week) == (10, 26)
    late = run_nexus_battery(scenario(horizon=100, warmup_end=30, analysis_window=50),
                             targets=[NexusTarget("supplier", "s1")])
    assert (late.warmup_week, late.start_week) == (30, 31)


def test_shards_are_the_battery(battery):
    a = run_nexus_battery(scenario(BACKUP), targets=[NexusTarget("supplier", "s1"),
                                                     NexusTarget("material", "m2")],
                          expected_warmup=battery.warmup_week,
                          expected_clean_digest=battery.clean_digest)
    b = run_nexus_battery(scenario(BACKUP), targets=[t for t in all_targets(scenario())
                                                     if t not in {NexusTarget("supplier", "s1"),
                                                                  NexusTarget("material", "m2")}])
    assert merge_shards([a.results(), b.results()]) == battery.results()
    with pytest.raises(NexusBatteryError, match="more than one shard"):
        merge_shards([a.results(), a.results()])


def test_a_shard_refuses_a_different_reference(battery):
    with pytest.raises(NexusBatteryError, match="warm-up week"):
        run_nexus_battery(scenario(BACKUP), targets=[NexusTarget("supplier", "s1")],
                          expected_warmup=battery.warmup_week + 1)
    with pytest.raises(NexusBatteryError, match="clean reference differs"):
        run_nexus_battery(scenario(THIN), targets=[NexusTarget("supplier", "s1")],
                          expected_clean_digest="0" * 64)


def test_zero_loss_says_why(battery):
    # s2's outage is covered by s3 through the backup policy: zero €, no backlog.
    s2 = by_id(battery)[("supplier", "s2")]
    assert s2.average_eur == 0.0 and s2.zero_reason == "absorbed"
    # Backordered demand waits instead of being lost: zero € in every column, a
    # backlog, and the row says so rather than reading as a harmless supplier.
    bo = {**THIN, "unmet_demand_handling": {"rule": "backorder", "backorder_horizon": 26}}
    row = run_nexus_battery(scenario(bo), targets=[NexusTarget("supplier", "s1")]).rows[0]
    assert row.average_eur == 0.0 and row.zero_reason == "backordered"
    # One week of demand (100 units) per week the outage outlasts the 3-week cover.
    assert row.backlog_by_duration[9] == pytest.approx(600.0)


def test_a_window_too_short_is_refused():
    with pytest.raises(NexusBatteryError, match="ends after the KPI window"):
        # KPI window weeks 10–22; a 9-week outage from week 26 would lie outside it.
        run_nexus_battery(scenario(horizon=60, warmup_end=10, analysis_window=13))


def test_the_stored_shape(battery):
    s = battery.summary()
    assert s["scenario"] == NEXUS_SCENARIO and len(s["scenario_hash"]) == 64
    assert s["targets"] == 5 and s["materials"] == 2 and s["suppliers"] == 3
    row = battery.results()[0]
    assert set(row) == {"entity_type", "entity_id", "metrics"}
    assert set(row["metrics"]["by_duration"]) == {str(d) for d in NEXUS_SCENARIO["durations_weeks"]}


def test_a_declared_variant_runs_one_duration_from_its_own_week():
    # Owner-requested: one 5-week outage from week 30, everything else shared.
    spec = nexus_variant(start_week=30, durations_weeks=[5])
    assert spec["durations_weeks"] == [5] and spec["start_week"] == 30
    assert {k: v for k, v in spec.items() if k not in ("start_week", "durations_weeks")} == \
        {k: v for k, v in NEXUS_SCENARIO.items() if k not in ("start_week", "durations_weeks")}
    assert nexus_scenario_hash(spec) != nexus_scenario_hash()
    b = run_nexus_battery(scenario(BACKUP, horizon=100, analysis_window=60), spec=spec)
    assert b.start_week == 30
    assert all(sorted(r.by_duration) == [5] and r.average_eur == r.by_duration[5]["mean"] for r in b.rows)
    s = b.summary()
    assert s["scenario"] == spec and s["scenario_hash"] == nexus_scenario_hash(spec)
    assert merge_shards([b.results()], spec) == b.results()


def test_the_default_is_unchanged_by_the_variant_machinery(battery):
    assert nexus_variant() == NEXUS_SCENARIO
    assert battery.summary()["scenario_hash"] == nexus_scenario_hash()
    assert sorted(battery.rows[0].by_duration) == NEXUS_SCENARIO["durations_weeks"]


def test_a_bad_variant_is_refused():
    with pytest.raises(NexusBatteryError):
        nexus_variant(durations_weeks=[])
    with pytest.raises(NexusBatteryError):
        nexus_variant(start_week=0)


def test_the_seed_and_replications_are_recorded():
    # Replication k draws from (seed, k) (stats/seeds.py, keyed — never by
    # sequential spawning), so seed 1 now and more replications later on the same
    # seed is one battery with more replications. The battery records both.
    spec = nexus_variant(durations_weeks=[5])
    t = [NexusTarget("supplier", "s1")]
    one = run_nexus_battery(scenario(THIN, model_seeds=1), targets=t, spec=spec)
    three = run_nexus_battery(scenario(THIN, model_seeds=3), targets=t, spec=spec)
    assert (one.replications, three.replications) == (1, 3)
    assert one.rows[0].by_duration[5]["n"] == 1 and three.rows[0].by_duration[5]["n"] == 3
    assert one.summary()["seed"] == three.summary()["seed"] == 42
