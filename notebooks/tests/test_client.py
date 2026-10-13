"""The HTTP client's error, retry and pagination behaviour, against a scripted transport."""
import json
from pathlib import Path

import pytest


class Scripted:
    """A transport that answers from a list of (status, headers, body)."""

    def __init__(self, *responses):
        self.responses, self.calls = list(responses), []

    def request(self, method, path, params=None, body=None, headers=None):
        self.calls.append((method, path, params, body, headers))
        return self.responses.pop(0)


def err(status, code, message="", headers=None, details=None):
    return status, headers or {}, {"error": {"code": code, "message": message, **({"details": details} if details else {})}}


@pytest.fixture(autouse=True)
def no_sleep(lib, monkeypatch):
    monkeypatch.setattr(lib["time"], "sleep", lambda s: None)


def client(lib, *responses):
    return lib["SuReSuite"](Scripted(*responses), live=True)


def test_error_envelope_becomes_a_typed_exception(lib):
    api = client(lib, err(403, "missing_scope", "this key does not have the write:runs scope",
                          headers={"X-Request-Id": "req-1"}))
    with pytest.raises(lib["SuReSuiteError"]) as e:
        api.get("/projects")
    assert (e.value.status, e.value.code, e.value.request_id) == (403, "missing_scope", "req-1")


def test_missing_scope_says_how_to_get_it(lib):
    api = client(lib, err(403, "missing_scope", "this key does not have the write:data scope"))
    with pytest.raises(lib["SuReSuiteError"]) as e:
        api.post("/projects/p/datasets:freeze")
    assert "write:data" in str(e.value) and "/developer" in str(e.value)


def test_rate_limited_is_retried(lib):
    api = client(lib, err(429, "rate_limited", headers={"Retry-After": "2"}), (200, {}, {"data": [], "next_cursor": None}))
    assert api.get("/projects") == {"data": [], "next_cursor": None}
    assert len(api.t.calls) == 2


def test_daily_quota_is_not_slept_through(lib):
    api = client(lib, err(429, "daily_quota_exceeded", headers={"Retry-After": "3600"}))
    with pytest.raises(lib["SuReSuiteError"]) as e:
        api.get("/projects")
    assert e.value.code == "daily_quota_exceeded" and len(api.t.calls) == 1


def test_gateway_hiccup_is_retried(lib):
    api = client(lib, err(503, "read_failed"), (200, {}, {"ok": True}))
    assert api.get("/x") == {"ok": True}


def test_pagination_follows_the_cursor(lib):
    api = client(lib, (200, {}, {"data": [1, 2], "next_cursor": "c1"}), (200, {}, {"data": [3], "next_cursor": None}))
    assert api.list_all("/projects") == [1, 2, 3]
    assert api.t.calls[1][2] == {"limit": 100, "cursor": "c1"}


def test_non_json_error_body(lib, monkeypatch):
    t = lib["HttpTransport"]("https://example.invalid/v1", "sk_test_x_y")

    class Resp:
        status_code, headers, content, text = 502, {}, b"<html>Bad gateway</html>", "<html>Bad gateway</html>"

        def json(self):
            raise ValueError("not json")

    monkeypatch.setattr(t.session, "request", lambda *a, **k: Resp())
    status, _, body = t.request("GET", "/projects")
    assert status == 502 and body["error"]["code"] == "non_json_response"


def test_terminal_statuses_are_the_workers(lib):
    assert lib["TERMINAL"] == ("done", "failed", "cancelled")


def test_dispatch_explains_a_gate_refusal(lib, capsys):
    findings = [{"severity": "warn", "message": "Disruption on \"material:M2\": skipped"}]
    api = client(lib, err(422, "validation_failed", details={"validation": "ack_required", "findings": findings}))
    with pytest.raises(lib["SuReSuiteError"]):
        api.dispatch("p", "s", "v")
    out = capsys.readouterr().out
    assert "skipped" in out and "acknowledge_warnings=True" in out


def test_dispatch_reuses_on_409(lib):
    run = {"id": "r1", "status": "done"}
    api = client(lib, err(409, "reuse_available", details={"reuse_candidate": {"run_id": "r1"}}), (200, {}, run))
    assert api.dispatch("p", "s", "v") == run


def test_idempotency_key_follows_the_request(lib):
    api = client(lib, *[(202, {}, {"run_id": "r", "status": "queued"}), (200, {}, {"id": "r", "status": "queued"})] * 3)
    api.dispatch("p", "s", "v")
    api.dispatch("p", "s", "v")
    api.dispatch("p", "s", "v", force_rerun=True)
    keys = [c[4]["Idempotency-Key"] for c in api.t.calls if c[0] == "POST"]
    assert keys[0] == keys[1] != keys[2]


def test_paired_compare_matches_the_golden_vector(lib):
    g = json.loads((Path(__file__).parent / "paired_compare_golden.json").read_text())
    table = lib["paired_compare"](g["a"], g["b"], ["fill_rate", "lost_sales_value"])
    for kpi, exp in g["expected"].items():
        assert table.loc[kpi, "pairs"] == exp["n"]
        assert table.loc[kpi, "delta"] == pytest.approx(exp["mean"], rel=1e-9)
        assert table.loc[kpi, "half_width"] == pytest.approx(exp["halfWidth"], rel=1e-9)
        assert (table.loc[kpi, "verdict"] != "no clear difference") == exp["separated"]
    assert table.loc["fill_rate", "verdict"] == "B better"


# ── a notebook never breaks halfway: the key is checked first ──
NEEDS = ["read:data", "read:policies", "read:runs", "write:runs"]


def key_info(*scopes, principal="personal"):
    return 200, {}, {"key_prefix": "ab12cd34", "env": "test", "principal": principal,
                     "scopes": list(scopes), "project_ids": None}


def live(lib, monkeypatch, *responses):
    t = Scripted(*responses)
    monkeypatch.setitem(lib, "HttpTransport", lambda base_url, api_key: t)
    return t


def test_a_key_with_every_needed_scope_stays_live(lib, monkeypatch):
    live(lib, monkeypatch, key_info(*NEEDS))
    api = lib["connect"]("https://x", "sk_test_k", demo_data=None, needs=NEEDS)
    assert api.live


def test_a_read_only_key_falls_back_to_the_demo_and_says_why(lib, monkeypatch, demo_data, capsys):
    live(lib, monkeypatch, key_info("read:data", "read:policies", "read:runs"))
    api = lib["connect"]("https://x", "sk_test_k", demo_data=demo_data, needs=NEEDS)
    out = capsys.readouterr().out
    assert not api.live
    assert "write:runs" in out and "/developer" in out and "read-only" in out and "DEMO mode" in out


def test_a_read_only_key_in_live_mode_stops_before_anything_runs(lib, monkeypatch, demo_data):
    live(lib, monkeypatch, key_info("read:data", "read:runs", principal="org"))
    with pytest.raises(lib["Stop"]) as e:
        lib["connect"]("https://x", "sk_test_k", demo_data=demo_data, needs=NEEDS, mode="live")
    assert "read:policies, write:runs" in str(e.value)
    assert e.value._render_traceback_() == [f"Stopped: {e.value}"]


def test_a_gateway_without_get_key_is_not_a_failure(lib, monkeypatch):
    live(lib, monkeypatch, err(404, "route_not_found", "no such route: GET /v1/key"))
    assert lib["connect"]("https://x", "sk_test_k", needs=NEEDS).live


def test_without_write_policies_the_newest_saved_version_is_used(lib, capsys):
    versions = [{"id": "v1", "label": "old", "created_at": "2026-01-01"},
                {"id": "v2", "label": "new", "created_at": "2026-02-01"}]
    api = client(lib, (200, {}, {"data": versions}), err(403, "missing_scope", "no write:policies"))
    assert lib["baseline_policy_version"](api, "p")["id"] == "v2"
    assert "newest saved version" in capsys.readouterr().out


def test_a_wrong_policy_version_id_says_so(lib):
    api = client(lib, (200, {}, {"data": [{"id": "v1"}]}))
    with pytest.raises(lib["Stop"]) as e:
        lib["baseline_policy_version"](api, "p", "nope")
    assert "POLICY_VERSION_ID nope" in str(e.value)


def test_a_wrong_scenario_id_says_so(lib):
    api = client(lib, (200, {}, {"data": [], "next_cursor": None}))
    with pytest.raises(lib["Stop"]) as e:
        lib["baseline_scenario"](api, "p", "nope")
    assert "SCENARIO_ID nope" in str(e.value)


def test_a_failed_run_stops_with_its_reason(lib):
    with pytest.raises(lib["Stop"]) as e:
        lib["require_done"]({"id": "r1", "status": "failed", "error_message": "worker lost"})
    assert "failed: worker lost" in str(e.value)
    assert lib["kpi_table"]({"aggregate_kpis": None}).empty
    assert lib["replications_frame"]([]).empty


def test_expired_series_can_be_skipped(lib, capsys):
    page = (200, {}, {"data": [], "next_cursor": None, "series": {"location": "expired"}})
    api = client(lib, page, page)
    assert api.series("r1", expired_ok=True) is None
    assert "force_rerun=True" in capsys.readouterr().out
    with pytest.raises(lib["SuReSuiteError"]):
        api.series("r1")
