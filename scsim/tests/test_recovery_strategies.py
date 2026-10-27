"""Recovery strategies reach the engine as the playbook states them (engine 0.8.2, §4 D114).

The scenario's playbook (`recovery_overrides`, merged over the policy version's
`recovery` family) is mapped by `_map_policies`. What these tests hold:

* `enabled: false` switches every recovery response off — the card's "Recovery
  enabled" switch was never read before 0.8.2.
* each strategy's parameter field reaches its plugin, and a blank one leaves the
  plugin's own default (a backup's lead time is then the backup lane's own).
* a response with no engine model is SAID in the run's warnings, not dropped.
* a backup source entered on the scenario (`backup_lanes`) is a backup-only link:
  never the material's primary however cheap, no planned share under P-S.2, added
  only when Backup supplier is on — and it changes the run when the primary is out.
"""
from __future__ import annotations

from scsim.core.engine import run_scenario
from scsim.io.project_map import (
    BomArc,
    MaterialRow,
    OutboundArc,
    ProductRow,
    ProjectData,
    ScenarioSettings,
    SupplierRow,
    SupplyArc,
    from_project_data,
)

OUTAGE = [{"target": "supplier:s1", "magnitude_pct": 100, "start_week": 12, "duration_weeks": 16}]


def _base(recovery: dict | None = None, **scenario_kw) -> ProjectData:
    """One supplier → one material → one product → one customer."""
    d = ProjectData(
        suppliers=[SupplierRow(id="s1")],
        materials=[MaterialRow(id="m1", cost=2.0)],
        products=[ProductRow(id="p1", sell_price=20.0, demand_mean=100.0,
                             production_capacity=200.0)],
        supply_arcs=[SupplyArc(supplier_id="s1", material_id="m1", unit_price=2.0,
                               lead_time=2, lead_time_unit="week")],
        bom=[BomArc(product_id="p1", material_id="m1", consumption_rate=1.0)],
        outbound=[OutboundArc(product_id="p1", customer_id="c1", unit_price=20.0,
                              volume=100.0, time_unit="week")],
        scenario=ScenarioSettings(**scenario_kw),
    )
    if recovery is not None:
        d.policies = {"default": {"recovery": recovery}}
    return d


BACKUP = {"material_id": "m1", "supplier_id": "s9", "supplier_name": "Spare Ltd",
          "lead_time_weeks": 3, "unit_price": 1.5}


def test_recovery_switched_off_applies_no_response():
    on = from_project_data(_base({"response": ["dual_source_activate", "capacity_flex",
                                               "mode_shift", "allocate_materials"]}))
    off = from_project_data(_base({"enabled": False,
                                   "response": ["dual_source_activate", "capacity_flex",
                                                "mode_shift", "allocate_materials"]}))
    plugins = {"backup_supplier", "short_term_capacity", "expedited_shipments",
               "material_allocation"}
    assert plugins <= set(on.scenario.policies)
    assert not plugins & set(off.scenario.policies)


def test_each_strategy_parameter_reaches_its_plugin():
    res = from_project_data(_base({
        "response": ["dual_source_activate", "capacity_flex", "mode_shift", "allocate_materials"],
        "backup_lead_time_weeks": 5, "overtime_cost_pct": 8, "expedite_cost_pct": 4,
        "allocation_horizon_weeks": 6, "annual_labor_cost": 9000,
    }))
    p = res.scenario.policies
    assert p["backup_supplier"]["backup_lead_time_weeks"] == 5
    assert p["short_term_capacity"]["overtime_premium_pct_of_price"] == 8
    assert p["expedited_shipments"]["premium_pct_of_cost"] == 4
    assert p["material_allocation"]["window_weeks"] == 6
    assert p["material_allocation"]["annual_cost"] == 9000


def test_a_blank_parameter_leaves_the_plugin_default():
    res = from_project_data(_base({"response": ["dual_source_activate", "capacity_flex"]}))
    # No backup lead time stated → each backup lane's own (the plugin's None).
    assert "backup_lead_time_weeks" not in res.scenario.policies["backup_supplier"]
    assert res.scenario.policies["short_term_capacity"] == {}


def test_a_response_with_no_engine_model_is_said():
    res = from_project_data(_base({"response": ["safety_stock_drawdown", "demand_shaping"]}))
    assert any(w.field == "response" and "no engine model" in w.reason for w in res.warnings)


def test_an_entered_backup_is_never_primary_even_when_cheaper():
    res = from_project_data(_base({"response": ["dual_source_activate"], "backup_lanes": [BACKUP]}))
    net = res.scenario.network
    links = {(l.supplier_id, l.material_id): l for l in net.supplier_links}
    assert links[("s9", "m1")].backup_only and links[("s9", "m1")].cost == 1.5
    assert net.primary_link("m1").supplier_id == "s1"      # 1.5 < 2.0, still not primary
    assert {s.id: s.name for s in net.suppliers}["s9"] == "Spare Ltd"
    assert any(w.field == "backup_lanes" and "not uploaded" in w.reason for w in res.warnings)


def test_an_entered_backup_is_added_only_when_backup_supplier_is_on():
    for rec in ({"response": ["capacity_flex"], "backup_lanes": [BACKUP]},
                {"enabled": False, "response": ["dual_source_activate"], "backup_lanes": [BACKUP]}):
        net = from_project_data(_base(rec)).scenario.network
        assert [l.supplier_id for l in net.supplier_links] == ["s1"]
        assert [s.id for s in net.suppliers] == ["s1"]


def test_an_entered_backup_duplicating_an_uploaded_lane_is_not_added():
    d = _base({"response": ["dual_source_activate"],
               "backup_lanes": [dict(BACKUP, supplier_id="s1")]})
    res = from_project_data(d)
    assert len(res.scenario.network.supplier_links) == 1
    assert any(w.field == "supplier_id" and "uploaded lane" in w.reason for w in res.warnings)


def test_multi_sourcing_gives_an_entered_backup_no_planned_share():
    from scsim.core.context import CompiledModel
    from scsim.policies.strategic.p_s2_proactive_multi_sourcing import ProactiveMultiSourcing

    d = _base({"response": ["dual_source_activate"], "backup_lanes": [BACKUP]})
    d.supply_arcs.append(SupplyArc(supplier_id="s2", material_id="m1", unit_price=2.5,
                                   lead_time=2, lead_time_unit="week"))
    scen = from_project_data(d).scenario
    model = CompiledModel(scen)
    plugin = ProactiveMultiSourcing(ProactiveMultiSourcing.Params())

    class _Ctx:  # setup reads only the model and writes policy_state
        def __init__(self, m):
            self.model, self.policy_state = m, {}

    ctx = _Ctx(model)
    plugin.setup(ctx)
    shares = ctx.policy_state[plugin.id]["shares"]
    backup = int(next(i for i in range(model.n_links) if model.link_backup_only[i]))
    assert shares[backup] == 0.0
    assert abs(sum(shares) - 1.0) < 1e-9          # the two uploaded lanes split it


def test_an_entered_backup_cuts_lost_sales_when_the_primary_is_out():
    kw = dict(replications=2, horizon_days=560, warmup_mode="manual", warmup_days=70)
    # Backup supplier on a single-sourced project with nothing entered is refused at
    # compile ("no alternative qualified source"), so the reference is the strategy off.
    without = _base({"response": []}, **kw)
    with_backup = _base({"response": ["dual_source_activate"], "backup_lanes": [BACKUP]}, **kw)
    for d in (without, with_backup):
        d.scenario.disruption_schedule = list(OUTAGE)
    a = run_scenario(from_project_data(without).scenario).aggregates["lost_sales_value"]["mean"]
    b = run_scenario(from_project_data(with_backup).scenario).aggregates["lost_sales_value"]["mean"]
    assert a > 0.0
    assert b < a


def test_the_engine_bridge_says_what_the_mapper_does():
    """`engineBridge.json` is the response → plugin table the platform reads (the card's
    `recoveryStrategies.test.ts`, the pre-run grader). It is hand-authored, so it is held
    here to the mapper, response by response — the comparison §4 D114 found missing."""
    import json
    from pathlib import Path

    bridge = json.loads((Path(__file__).resolve().parents[2] / "supabase" / "functions" / "_shared"
                         / "engineBridge.json").read_text())["recovery_response_to_policy"]
    recovery_plugins = {"backup_supplier", "expedited_shipments", "short_term_capacity",
                        "early_warning_failover", "material_allocation"}
    for response, plugin in bridge.items():
        if plugin == "safety_stock_materials":
            # P-P.3 always runs (the /policies buffer); the response adds its windows.
            pol = from_project_data(_base({"response": [response], "safety_stock_windows": [WINDOW]})
                                    ).scenario.policies
            assert pol[plugin].get("windows"), (response, pol[plugin])
            continue
        got = set(from_project_data(_base({"response": [response]})).scenario.policies)
        assert got & recovery_plugins == {plugin}, (response, got)
    for unmapped in ("demand_shaping",):
        got = set(from_project_data(_base({"response": [unmapped]})).scenario.policies)
        assert not got & recovery_plugins, (unmapped, got)


# ── P-P.3 disruption buffer windows (engine 0.8.3): the card's Safety stock ─────

WINDOW = {"material_id": "m1", "days": 28, "start_week": 6, "end_week": 28}
KW = dict(replications=2, horizon_days=560, warmup_mode="manual", warmup_days=70)


def _run(recovery: dict) -> dict:
    d = _base(recovery, **KW)
    d.scenario.disruption_schedule = list(OUTAGE)
    return run_scenario(from_project_data(d).scenario).aggregates


def test_a_buffer_window_reaches_p_p3_only_when_safety_stock_is_on():
    on = from_project_data(_base({"response": ["safety_stock_drawdown"],
                                  "safety_stock_windows": [WINDOW]})).scenario.policies
    assert on["safety_stock_materials"]["windows"] == [dict(WINDOW, days=28.0)]
    for rec in ({"response": [], "safety_stock_windows": [WINDOW]},
                {"enabled": False, "response": ["safety_stock_drawdown"], "safety_stock_windows": [WINDOW]}):
        assert "windows" not in from_project_data(_base(rec)).scenario.policies["safety_stock_materials"]


def test_safety_stock_on_without_a_window_is_said():
    res = from_project_data(_base({"response": ["safety_stock_drawdown"]}))
    assert any(w.field == "safety_stock_windows" and "nothing changes" in w.reason for w in res.warnings)
    assert not any("no engine model" in w.reason for w in res.warnings)


def test_a_malformed_or_foreign_window_is_skipped_with_its_reason():
    res = from_project_data(_base({"response": ["safety_stock_drawdown"], "safety_stock_windows": [
        {"material_id": "m1", "days": 14, "start_week": 20, "end_week": 20},   # empty window
        {"material_id": "zz", "days": 14, "start_week": 5, "end_week": 9},     # unknown material
    ]}))
    assert res.scenario.policies["safety_stock_materials"]["windows"] == [
        {"material_id": "zz", "days": 14.0, "start_week": 5, "end_week": 9}]
    assert any(w.field == "safety_stock_windows" and "skipped" in w.reason for w in res.warnings)
    assert any(w.field == "windows" and "does not simulate" in w.reason for w in res.warnings)


def test_under_mrp_the_window_is_said_to_change_nothing():
    d = _base({"response": ["safety_stock_drawdown"], "safety_stock_windows": [WINDOW]})
    d.policies["default"]["inventory"] = {"type": "mrp"}
    res = from_project_data(d)
    assert any(w.field == "windows" and "MRP" in w.reason for w in res.warnings)


def test_a_buffer_window_cuts_lost_sales_and_costs_holding_only_inside_it():
    without = _run({"response": []})
    with_win = _run({"response": ["safety_stock_drawdown"], "safety_stock_windows": [WINDOW]})
    assert with_win["lost_sales_value"]["mean"] < without["lost_sales_value"]["mean"]
    # The extra holding is the window's units at the material's weekly holding rate,
    # for the window's weeks inside the measured window (warm-up ends at week 10):
    # 100/wk · 28/7 = 400 units · (2.0 · 20 % / 52) · (28 − 10) weeks.
    extra = with_win["cost_ss_holding"]["mean"] - without["cost_ss_holding"]["mean"]
    assert abs(extra - 400 * (2.0 * 0.20 / 52.0) * 18) < 1e-6


def test_holding_is_booked_for_the_windows_weeks_and_no_others():
    # Two weeks, 40–41, after the outage has ended: exactly two weeks of holding.
    late = _run({"response": ["safety_stock_drawdown"], "safety_stock_windows": [
        dict(WINDOW, start_week=40, end_week=42)]})
    without = _run({"response": []})
    extra = late["cost_ss_holding"]["mean"] - without["cost_ss_holding"]["mean"]
    assert abs(extra - 400 * (2.0 * 0.20 / 52.0) * 2) < 1e-6
