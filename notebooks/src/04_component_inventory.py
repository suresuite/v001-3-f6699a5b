# %% [markdown]
# # SuReSuite 04 · Component inventory and disruptions
#
# **You will:** load your project's real data and the policies as they are on /policies now,
# run the baseline on your own machine, trace every material's stock week by week, knock out
# each supplier in turn, and follow the worst one down to the materials and products it hits.
# **Time:** about 20 minutes (longer on a large project: step 5 runs one simulation per target).
# **You need:** nothing for demo mode; with a key, `read:data` and `read:policies` (`read:runs`
# to use your saved scenario). Every user can create that key on /developer. `write:data` and
# `write:policies` (admins and modelers) let the notebook freeze your data and save your policies
# first, so it never has to work from an older copy.
#
# Nothing here changes your project. It runs on **this machine**, so it costs no quota.
#
# **Two limits:** the material traces in steps 4 and 6 are **one seed** (the engine keeps
# per-material weeks only for a single-replication run); the KPIs in steps 3 and 5 average over
# every replication. A sub-assembly has no stock line of its own: you trace its components.

# %% include: config

# %% include: setup

# %% include: library

# %% include: local

# %% include: study

# %% include: demo_data baseline

# %% [markdown]
# ## Try changing
# - `DATA_SOURCE`, `POLICY_SOURCE` — `"current"` follows the project as it is now; pin a version id to repeat a study.
# - `REPLICATIONS` — `None` uses your scenario's; fewer is faster, more gives tighter intervals.
# - `MATERIALS_TO_TRACE` — material ids from step 2; `[]` picks the riskiest.
# - `INSPECTION_SEED` — pin the one world the material traces show; `None` lets step 7 pick a typical one.
# - `DISRUPTION_TARGETS`, `START_DAY`, `OUTAGE_DAYS`, `MAGNITUDE_PCT` — what to knock out, when, how long, how hard.
# - `SUPPLIER_ID` (in the CONFIG cell) — the outage to follow in step 6; `""` = the worst one.

# %%
DATA_SOURCE = "current"      # "current" | "latest" (newest frozen version) | a dataset version id
POLICY_SOURCE = "current"    # "current" = /policies as it is now | "pinned" = POLICY_VERSION_ID exactly
REPLICATIONS = None          # None = the scenario's replications
INSPECTION_SEED = None       # None = step 5 shows the baseline's first replication, step 7 the most typical seed
SEED_CANDIDATES = 6          # seeds step 7 tries when picking the most typical one
MATERIALS_TO_TRACE = []      # e.g. ["M2", "M6"]
N_AUTO_MATERIALS = 3
DISRUPTION_TARGETS = []      # supplier ids and/or "plant"; [] = the most exposed suppliers + the plant
MAX_AUTO_TARGETS = 10
INCLUDE_SAVED_STRESS_TESTS = True  # also run the project's own stress-test scenarios (Simulation Lab)
START_DAY, OUTAGE_DAYS, MAGNITUDE_PCT = 140, 42, 100
MAX_ROWS = 40                # long tables show this many rows; the export has all of them
VERIFY_ON_PLATFORM = False   # True = also run the baseline on the platform and compare (write:runs; uses quota)
EXPORT_XLSX = "component_inventory_study.xlsx"   # "" = no export

# %% [markdown]
# ## 1 · Connect, and what this key can do
# **Expect:** your project, then a table of what the key allows and what the notebook does without it.

# %%
import matplotlib.colors as mcolors

api = connect(BASE_URL, API_KEY, DEMO_DATA, needs=["read:data", "read:policies"], mode=MODE)
LIVE = api.live
project = pick_project(api, PROJECT_ID)
PID = project["id"]
# The platform reads the project's model to decide how a product with no fulfillment mode of
# its own is made (make-to-stock or make-to-order). A local run must be told the same.
PROJECT_MODEL = project.get("supply_chain_model")
print(f"supply chain model: {PROJECT_MODEL or 'not set (make-to-order)'}")
SCOPES = key_scopes(api)
can = SCOPES.__contains__
display(key_table(SCOPES))

# %% [markdown]
# ## 2 · Load the project's data
# A run reads a **frozen dataset version** — your tables at one moment, identified by its
# `graph_hash`. `"current"` freezes the data now when the key may (an unchanged project returns
# the version it already has); otherwise it takes the newest version and says how old it is.
# Versions are kept in `suresuite_cache/`, so running again does not download them again.
# **Expect:** the version used, the size of every table, and a data check.

# %%
data = load_dataset(api, PID, DATA_SOURCE, SCOPES, LIVE, "notebook 04")
print(data)
T = input_tables(data)
display(pd.DataFrame({"rows": {k: len(v) for k, v in T.items()}}).T)

# %% [markdown]
# **The bill of materials, flattened.** Units of each purchased material per unit of each product,
# through any sub-assemblies (the multi-level BOM wins when it has rows, as in the engine).

# %%
BOM = flat_bom(T)
lanes = supply_lanes(T)
mats = T["materials"].assign(material_id=lambda d: col(d, "material_id").astype(str)).set_index("material_id")
prods = T["products"].assign(product_id=lambda d: col(d, "product_id").astype(str)).set_index("product_id")
n_sources = lanes.groupby("material_id")["supplier_id"].nunique()
check = data_check(T, BOM, lanes)
display(check.set_index("check")[["count", "items"]])

# %% [markdown]
# ## 3 · Load the policies as they are now
# A run reads a **policy version**. `"current"` compares your saved version with /policies as it is
# now: if they agree, the saved version is used (exact, with its `policy_hash`); if not, the key saves
# a new version when it may (an unchanged configuration is never saved twice), and otherwise the
# notebook rebuilds the current policies here from /policies and the saved version, and says so.
# **Expect:** what differs between the saved version and /policies, and which one the runs use.

# %%
pol, drift, now_fam = load_policies(api, PID, POLICY_SOURCE, POLICY_VERSION_ID, SCOPES, "notebook 04")
if len(drift):
    display(styled(capped(drift, "differences"), caption="Saved version vs /policies now"))
settings, overrides = policy_tables(pol, now_fam)
if len(settings):
    display(styled(capped(settings, "settings"),
                   caption=f"Project-wide settings the runs use — fulfillment strategy {pol.snapshot.get('fulfillment_strategy')}"))
if len(overrides):
    display(styled(overrides, caption=f"{int(overrides.iloc[:, 0].sum())} per-item overrides (they win over the project-wide settings)"))

# %% [markdown]
# ## 4 · Run the baseline on this machine
# The frame (horizon, warm-up, replications, seed, recovery playbook) is your saved baseline scenario's,
# so the numbers are the Simulation Lab's. The engine is the platform's current build, installed through
# the API once per environment.
# **Expect:** the scenario used, the engine's notes on how it read your data, the KPIs, and four charts.

# %%
scenario, FRAME, stress_saved = study_scenario(api, PID, SCENARIO_ID, SCOPES, REPLICATIONS)
RUN_LOCAL = ensure_engine(api, LIVE)


def simulate_here(disruptions=None, **over):
    """One run on this machine with the platform's inputs: this data, these policies, this frame,
    and the project's model."""
    return simulate(data, pol, scenario={**scenario, **FRAME, **over}, disruptions=disruptions or [],
                    project_model=PROJECT_MODEL)


if RUN_LOCAL:
    started = time.time()
    base = simulate_here()
    RUN_SECONDS = time.time() - started
    WARMUP = int(base["run"].get("warmup_detected_at") or 0)
    print(f"{FRAME.get('replications')} replications in {RUN_SECONDS:.1f}s · engine {base['run'].get('code_version')} · "
          f"warm-up ends week {WARMUP}")
    notes = pd.DataFrame(base["run"].get("mapping_warnings") or [], columns=["level", "entity", "field", "reason"])
    warn = notes[notes.level == "warn"]
    if len(warn):
        display(styled(capped(warn.groupby(["field", "reason"]).size().rename("items").sort_values(ascending=False)
                              .to_frame().reset_index(), "notes"),
                       caption=f"How the engine read your data — {len(warn)} warning(s)"))
    display(kpi_table(base["run"])[["measure", "mean", "± 95% CI"]])

# %%
COLORS = {"base": "#2a78d6", "shock": "#d9480f", "transit": "#7a5af8", "orders": "#94a3b8", "use": "#0f766e",
          "fg": "#008300", "zero": "#e03131", "window": "#5f6b7a"}


def band(ax, df, column, color, label, scale=1.0):
    """Mean across replications with the 10th–90th percentile band."""
    g = df.groupby("week")[column]
    m = g.mean() * scale
    ax.plot(m.index, m.values, color=color, linewidth=1.8, label=label)
    ax.fill_between(m.index, g.quantile(0.1) * scale, g.quantile(0.9) * scale, color=color, alpha=0.15, linewidth=0)


def marks(ax, window=None, warmup=None, legend=True):
    if warmup:
        ax.axvline(warmup, color=COLORS["window"], linestyle=":", linewidth=1, label="warm-up ends" if legend else None)
    if window:
        ax.axvspan(*window, color=COLORS["window"], alpha=0.12, linewidth=0, label="disruption" if legend else None)
    ax.spines[["top", "right"]].set_visible(False)


if RUN_LOCAL:
    S = base["series"]
    fig, axes = plt.subplots(2, 2, figsize=(11, 6))
    band(axes[0, 0], S, "fill_rate", COLORS["base"], "fill rate", 100)
    axes[0, 0].set_title("Fill rate (%)", fontsize=10)
    band(axes[0, 1], S, "on_hand_value", COLORS["base"], "materials")
    band(axes[0, 1], S, "fg_value", COLORS["fg"], "finished goods")
    axes[0, 1].set_title("Inventory value", fontsize=10)
    band(axes[1, 0], S, "backlog_units", COLORS["shock"], "backlog")
    axes[1, 0].set_title("Backlog (units)", fontsize=10)
    if S.get("plant_capacity_units") is not None and S["plant_capacity_units"].fillna(0).gt(0).any():
        S = S.assign(plant=100 * S.plant_capacity_used_units / S.plant_capacity_units.replace(0, np.nan),
                     suppliers=100 * S.supplier_capacity_used_units / S.supplier_capacity_units.replace(0, np.nan))
        band(axes[1, 1], S, "plant", COLORS["fg"], "plant")
        band(axes[1, 1], S, "suppliers", COLORS["transit"], "suppliers")
    axes[1, 1].set_title("Capacity used (%)", fontsize=10)
    for ax in axes.flat:
        marks(ax, warmup=WARMUP, legend=ax is axes[0, 0])
        ax.set_xlabel("week")
        ax.legend(fontsize=8, frameon=False)
    fig.suptitle(f"Baseline — mean of {FRAME.get('replications')} replications, band 10th–90th percentile", fontsize=10)
    plt.tight_layout()
    plt.show()

# %% [markdown]
# ## 5 · Every material, week by week
# One more run with **one** replication and the engine's inspection trace on: each material's stock on
# hand, in transit and orders placed, and each product's demand, production and deliveries. It is the
# baseline's first replication, the same world as one line in step 4. Use is each product's production
# times its BOM. Weeks before the warm-up ends are left out.
# **Expect:** every material ranked by risk, then a chart per traced material.

# %%
def inspect(seed, disruptions=None):
    return inspect_run(data, pol, {**scenario, **FRAME}, PROJECT_MODEL, seed, disruptions)


def material_table(frames, w0):
    post = lambda df: df[df.index >= w0]
    oh, use = post(frames[("material", "on_hand")]), post(use_of(frames, BOM))
    zero = oh <= 1e-6
    avg_use = use.mean().replace(0, np.nan)
    return pd.DataFrame({
        "suppliers": [", ".join(sorted(set(lanes.supplier_id[lanes.material_id == m]))) or "—" for m in oh.columns],
        "avg on hand": oh.mean(), "min on hand": oh.min(), "weeks at zero": zero.sum(),
        "first stockout": zero.apply(lambda c: c.idxmax() if c.any() else np.nan),
        "avg in transit": post(frames[("material", "in_transit")]).mean(), "avg use / wk": use.mean(),
        "min cover (wk)": oh.min() / avg_use, "ordered": post(frames[("material", "orders")]).sum(),
    }, index=oh.columns).rename_axis("material")


if RUN_LOCAL:
    SEED5 = INSPECTION_SEED if INSPECTION_SEED is not None else int(FRAME.get("seed", 42))
    insp_run, BASE = inspect(SEED5)
    W0 = int(insp_run.get("warmup_detected_at") or WARMUP)
    mt = material_table(BASE, W0)
    mt = mt.assign(_c=mt["min cover (wk)"].fillna(np.inf)).sort_values(["weeks at zero", "_c"], ascending=[False, True]).drop(columns="_c")
    display(styled(capped(mt, "materials"), shade=["weeks at zero"],
                   fmt={c: "{:,.1f}" for c in mt.columns if c not in ("suppliers", "weeks at zero", "first stockout")}
                   | {"weeks at zero": "{:,.0f}", "first stockout": "{:,.0f}"},
                   caption=f"Every material, riskiest first — seed {SEED5}, weeks {W0}+"))
    TRACE = [m for m in MATERIALS_TO_TRACE if m in mt.index] or list(mt.index[:N_AUTO_MATERIALS])
    if set(MATERIALS_TO_TRACE) - set(mt.index):
        print("not a material of this run (check the ids above):", sorted(set(MATERIALS_TO_TRACE) - set(mt.index)))
    print("tracing:", ", ".join(TRACE))

# %%
def plot_material(m, frames, other=None, window=None, labels=("baseline", None)):
    oh, it, orders, use = (frames[("material", "on_hand")], frames[("material", "in_transit")],
                           frames[("material", "orders")], use_of(frames, BOM))
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(11, 4.4), sharex=True, gridspec_kw={"height_ratios": [3, 2]})
    a1.plot(oh.index, oh[m], color=COLORS["base"], linewidth=2, label=f"on hand · {labels[0]}")
    a1.plot(it.index, it[m], color=COLORS["transit"], linewidth=1.2, linestyle="--", label=f"in transit · {labels[0]}")
    show = oh
    if other is not None:
        show = other[("material", "on_hand")]
        a1.plot(show.index, show[m], color=COLORS["shock"], linewidth=2, label=f"on hand · {labels[1]}")
        a1.plot(other[("material", "in_transit")].index, other[("material", "in_transit")][m], color=COLORS["shock"],
                linewidth=1.2, linestyle="--", alpha=0.7, label=f"in transit · {labels[1]}")
        orders, use = other[("material", "orders")], use_of(other, BOM)
    out = show.index[(show[m] <= 1e-6) & (show.index >= W0)]
    if len(out):
        a1.scatter(out, [0] * len(out), color=COLORS["zero"], marker="v", s=26, zorder=5, label="stockout")
    users = ", ".join(sorted(set(BOM.product_id[BOM.material_id == m]))) or "—"
    a1.set_title(f"{m} · {mats['name'].get(m, '') if 'name' in mats else ''} — from {mt.loc[m, 'suppliers']} · used by {users}",
                 fontsize=10)
    a1.set_ylabel("units")
    a2.bar(orders.index, orders[m], color=COLORS["orders"], width=0.8, label="ordered")
    a2.plot(use.index, use[m], color=COLORS["use"], linewidth=1.6, label="used")
    a2.set_ylabel("units / week")
    a2.set_xlabel("week")
    for ax in (a1, a2):
        marks(ax, window, W0, legend=ax is a1)
        ax.legend(fontsize=8, frameon=False, loc="upper left", bbox_to_anchor=(1.01, 1.0))
    plt.tight_layout()
    plt.show()


if RUN_LOCAL:
    for m in TRACE:
        plot_material(m, BASE)
    mrp = [k for k in ("mrp_need", "mrp_on_hand", "mrp_on_the_way", "mrp_net") if ("material", k) in BASE]
    for m in TRACE if mrp else []:
        rec = pd.DataFrame({k: BASE[("material", k)].get(m) for k in mrp})
        if rec.notna().any().any() and rec.abs().to_numpy().sum() > 0:
            display(styled(rec[rec.index >= W0].head(12).T, fmt="{:,.0f}", caption=f"{m} — the MRP record, first 12 weeks"))

# %% [markdown]
# ## 6 · Knock out each supplier
# Each target ships nothing (or `MAGNITUDE_PCT` less) for `OUTAGE_DAYS` from `START_DAY`; deliveries are
# deferred, not lost. Every run uses the baseline's random draws, so each is compared with it
# replication by replication. Suppliers are chosen by **exposure**: what they ship that no one else does.
# Your saved stress tests from the Simulation Lab run too. A target must be a supplier id or `plant`:
# the engine skips any other, and the table says so.
# **Expect:** the targets and the time it will take, then the impact of each, worst first.

# %%
if RUN_LOCAL:
    sole = set(n_sources[n_sources == 1].index)
    exposure = (lanes.assign(sole=lanes.material_id.isin(sole))
                .groupby("supplier_id")
                .agg(materials=("material_id", lambda s: ", ".join(sorted(set(s)))),
                     sole_sourced=("sole", "sum"),
                     exposed_spend=("spend", lambda s: s[lanes.loc[s.index, "material_id"].isin(sole)].sum()),
                     spend=("spend", "sum"))
                .sort_values(["exposed_spend", "sole_sourced", "spend"], ascending=False))
    targets = list(DISRUPTION_TARGETS) or list(exposure.index[:MAX_AUTO_TARGETS]) + ["plant"]
    if SUPPLIER_ID and SUPPLIER_ID not in targets:
        targets.insert(0, SUPPLIER_ID)
    unknown = [t for t in targets if t != "plant" and t not in set(col(T["suppliers"], "supplier_id").astype(str))]
    if unknown:
        print("not a supplier id of this project — skipped:", unknown)
    cases = {f"{t} out": [outage(t, START_DAY, OUTAGE_DAYS, MAGNITUDE_PCT)] for t in targets if t not in unknown}
    if INCLUDE_SAVED_STRESS_TESTS:
        cases.update({f"saved: {s['name']}": s["disruption_schedule"] for s in stress_saved})
    display(styled(capped(exposure, "suppliers"), fmt={"exposed_spend": "{:,.0f}", "spend": "{:,.0f}"},
                   shade=["exposed_spend"], cmap="Oranges", caption="Suppliers by exposure (weekly spend)"))
    print(f"{len(cases)} runs × {FRAME.get('replications')} replications — about {len(cases) * RUN_SECONDS:.0f}s")

    shocks = {}
    for name, events in cases.items():
        started = time.time()
        r = simulate_here(disruptions=events)
        applied = any("recovery_measurable" in (x.get("kpis") or {}) for x in r["replications"])
        shocks[name] = {"events": events, "result": r, "applied": applied}
        print(f"  {name:<34} {time.time() - started:5.1f}s" + ("" if applied else "  — NOT APPLIED: the engine skipped every event"))

# %%
IMPACT = [("fill_rate", "Δ fill rate (pp)", 100), ("lost_units", "Δ lost units", 1),
          ("lost_sales_value", "Δ lost sales", 1), ("max_backlog", "Δ peak backlog", 1),
          ("avg_on_hand_value", "Δ avg material stock value", 1)]


def paired_values(base_reps, reps, kpi):
    """(disrupted − baseline) for each replication, matched on the same random draws."""
    key = lambda r: (int((r.get("kpis") or {}).get("model_rep", r["rep_index"])), int((r.get("kpis") or {}).get("event_rep") or 0))
    a = {key(r): (r.get("kpis") or {}).get(kpi) for r in base_reps}
    return np.array([(r.get("kpis") or {}).get(kpi) - a[key(r)] for r in reps
                     if (r.get("kpis") or {}).get(kpi) is not None and a.get(key(r)) is not None], dtype=float)


def paired(base_reps, reps, kpi):
    """Mean and 95 % half-width of (disrupted − baseline), replication by replication."""
    d = paired_values(base_reps, reps, kpi)
    if len(d) < 2:
        return (d.mean() if len(d) else np.nan), np.nan
    return d.mean(), T95.get(len(d) - 1, 1.96) * d.std(ddof=1) / np.sqrt(len(d))


if RUN_LOCAL:
    rows = []
    for name, s in shocks.items():
        row = {"case": name, "applied": "yes" if s["applied"] else "NO"}
        for k, label, scale in IMPACT:
            m, hw = paired(base["replications"], s["result"]["replications"], k)
            row[label], row[label + " ±"] = m * scale, hw * scale
        reps = replications_frame(s["result"]["replications"])
        row["survives (wk)"] = reps["tts_weeks"].mean() if "tts_weeks" in reps else np.nan
        row["recovers (wk)"] = reps["ttr_weeks"].mean() if "ttr_weeks" in reps else np.nan
        m, hw = row["Δ lost sales"], row["Δ lost sales ±"]
        row["verdict"] = "no clear effect" if not abs(m) > (hw if hw == hw else 0) else ("loses sales" if m > 0 else "gains")
        rows.append(row)
    impact = pd.DataFrame(rows).set_index("case").sort_values("Δ lost sales", ascending=False)
    display(styled(capped(impact, "cases"), shade=["Δ lost sales", "Δ lost units"],
                   fmt={"Δ fill rate (pp)": "{:+.2f}", "Δ fill rate (pp) ±": "±{:.2f}", "Δ lost units": "{:+,.0f}",
                        "Δ lost units ±": "±{:,.0f}", "Δ lost sales": "{:+,.0f}", "Δ lost sales ±": "±{:,.0f}",
                        "Δ peak backlog": "{:+,.0f}", "Δ peak backlog ±": "±{:,.0f}",
                        "Δ avg material stock value": "{:+,.0f}", "Δ avg material stock value ±": "±{:,.0f}",
                        "survives (wk)": "{:.1f}", "recovers (wk)": "{:.1f}"},
                   caption=f"Impact vs baseline — mean of {FRAME.get('replications')} paired replications, ± 95 % interval"))
    print("survives = weeks the chain kept serving after the event began; recovers = weeks back to normal service")

    shown = impact.iloc[:20][::-1]
    fig, axes = plt.subplots(1, 2, figsize=(11, 0.36 * len(shown) + 1.4))
    for ax, label in zip(axes, ["Δ lost sales", "Δ fill rate (pp)"]):
        vals, err = shown[label], shown[label + " ±"].fillna(0)
        ax.barh(range(len(shown)), vals, xerr=err, error_kw={"linewidth": 0.8, "capsize": 2},
                color=[COLORS["shock"] if abs(v) > e else "#adb5bd" for v, e in zip(vals, err)])
        ax.set_yticks(range(len(shown)), shown.index, fontsize=8)
        ax.axvline(0, color="#495057", linewidth=0.8)
        ax.set_title(label, fontsize=10)
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Worst first — grey: not separable from noise at 95 %", fontsize=10)
    plt.tight_layout()
    plt.show()

# %% [markdown]
# ## 7 · Follow one outage to the materials
# The outage in `SUPPLIER_ID`, or else the worst supplier outage, runs again as one replication, with and
# without the outage on the **same seed**, so the two worlds share every random draw and differ only by
# the outage. An outage often hurts in some worlds and not at all in others (it depends on where it
# falls in the reorder cycle), so the notebook says how often it hurt, tries `SEED_CANDIDATES` seeds, and
# follows a world where it hurt about as much as it usually does when it hurts.
# **Expect:** the seed chosen and why, a map of how every material's stock moved, a table of the
# materials touched, a chart for each, and what each product lost.

# %%
if RUN_LOCAL:
    applied = [c for c in impact.index if shocks[c]["applied"]]
    FOCUS = f"{SUPPLIER_ID} out" if f"{SUPPLIER_ID} out" in shocks else \
        next((c for c in applied if c.endswith(" out") and c != "plant out"), applied[0] if applied else None)
    if FOCUS is None:
        raise Stop("no disruption reached the engine — check the targets in step 6")
    events = shocks[FOCUS]["events"]
    WINDOW = effective_window(events[0], base["run"])
    hit_supplier = events[0]["target"] if len(events) == 1 else None
    lost = lambda frames: frames[("product", "lost_units")].loc[W0:].to_numpy().sum() if ("product", "lost_units") in frames else 0.0
    rep_d = paired_values(base["replications"], shocks[FOCUS]["result"]["replications"], "lost_units")
    hurt_d = rep_d[rep_d > 0.5]
    typical = float(np.median(hurt_d)) if len(hurt_d) else 0.0
    print(f"{FOCUS} cost sales in {len(hurt_d)} of {len(rep_d)} replications"
          + (f" — when it did, a median {typical:,.0f} units" if len(hurt_d) else ""))
    seeds = [INSPECTION_SEED] if INSPECTION_SEED is not None else [int(FRAME.get("seed", 42)) + i for i in range(SEED_CANDIDATES)]
    tried = {}
    for sd in seeds:
        b = BASE if sd == SEED5 else inspect(sd)[1]
        o = inspect(sd, events)[1]
        tried[sd] = (b, o, lost(o) - lost(b))
    hurting = {sd: t for sd, t in tried.items() if t[2] > 0.5} if len(hurt_d) else {}
    SEED7 = min(hurting or tried, key=lambda sd: abs(tried[sd][2] - typical))
    if len(hurt_d) and not hurting:
        print(f"none of the {len(tried)} seeds tried lost sales — raise SEED_CANDIDATES to find one that does")
    BASE7, SHOCK, _ = tried[SEED7]
    if len(tried) > 1:
        display(styled(pd.DataFrame({"Δ lost units": {sd: t[2] for sd, t in tried.items()}}).rename_axis("seed").T,
                       fmt="{:+,.0f}", caption=f"{FOCUS}, one world per seed"))
    print(f"following: {FOCUS} — weeks {WINDOW[0]}–{WINDOW[1]}, seed {SEED7}, where it loses {tried[SEED7][2]:+,.0f} units")

    oh_b, oh_s = BASE7[("material", "on_hand")], SHOCK[("material", "on_hand")]
    rel = (oh_s - oh_b) / oh_b[oh_b.index >= W0].mean().replace(0, np.nan)
    rel = rel.loc[:, rel.abs().max().sort_values(ascending=False).index]
    rel = rel.loc[:, rel.abs().max() > 0.01].iloc[:, :MAX_ROWS]
    if rel.shape[1]:
        lim = float(min(1.0, np.nanmax(np.abs(rel.to_numpy()))))
        fig, ax = plt.subplots(figsize=(11, 0.3 * rel.shape[1] + 1.4))
        im = ax.imshow(rel.T.to_numpy(), aspect="auto", cmap="RdBu", norm=mcolors.TwoSlopeNorm(0, -lim, lim),
                       extent=[-0.5, rel.index.max() + 0.5, rel.shape[1] - 0.5, -0.5])
        ax.set_yticks(range(rel.shape[1]), rel.columns, fontsize=8)
        for x in WINDOW:
            ax.axvline(x, color="#212529", linewidth=0.8, linestyle="--")
        ax.set_xlabel("week")
        ax.set_title(f"Stock with {FOCUS} minus baseline, as a share of the baseline average (red = less)", fontsize=10)
        fig.colorbar(im, ax=ax, shrink=0.8, format=lambda v, _: f"{v:+.0%}")
        plt.tight_layout()
        plt.show()
    else:
        print("no material's stock moved by more than 1 % in this seed")

# %%
def back_in_range(m, slack=0.05):
    """The week from which stock stays inside the baseline's own range (its min to max after warm-up).
    A reorder cycle shifted in time stays inside it, which a week-by-week comparison would not."""
    b = oh_b.loc[oh_b.index >= W0, m]
    s = oh_s.loc[oh_s.index >= WINDOW[0], m]
    outside = s[(s < b.min() * (1 - slack)) | (s > b.max() * (1 + slack))]
    if outside.empty:
        return "never left"
    return "not by the end" if outside.index.max() >= oh_s.index.max() else int(outside.index.max()) + 1


if RUN_LOCAL:
    mb, ms = material_table(BASE7, W0), material_table(SHOCK, W0)
    direct = set(lanes.material_id[lanes.supplier_id == hit_supplier]) if hit_supplier else set()
    touched = pd.DataFrame({
        "hit directly": ["yes" if m in direct else "" for m in mb.index], "suppliers": mb["suppliers"],
        "min on hand · base": mb["min on hand"], "min on hand · outage": ms["min on hand"],
        "weeks at zero · base": mb["weeks at zero"], "weeks at zero · outage": ms["weeks at zero"],
        "first stockout": ms["first stockout"], "Δ avg on hand": ms["avg on hand"] - mb["avg on hand"],
        "Δ used": (ms["avg use / wk"] - mb["avg use / wk"]) * (len(oh_b) - W0),
        "back in normal range": [back_in_range(m) for m in mb.index],
    }, index=mb.index)
    moved = (touched["Δ avg on hand"].abs() > 1e-6) | (touched["weeks at zero · outage"] != touched["weeks at zero · base"])
    touched = touched[moved | touched.index.isin(direct)].sort_values(["hit directly", "weeks at zero · outage"], ascending=False)
    display(styled(capped(touched, "materials"), shade=["weeks at zero · outage"],
                   fmt={c: "{:,.0f}" for c in ("min on hand · base", "min on hand · outage", "weeks at zero · base",
                                               "weeks at zero · outage", "first stockout")}
                   | {"Δ avg on hand": "{:+,.0f}", "Δ used": "{:+,.0f}"},
                   caption=f"Materials touched by {FOCUS} — seed {SEED7}, weeks {W0}+"))
    print("normal range = the material's own baseline min..max after warm-up.\n"
          "Δ used below zero on a material the outage did not hit: production stopped for want of ANOTHER material.")
    for m in list(dict.fromkeys([*touched.index[:4], *[t for t in TRACE if t in touched.index]])):
        plot_material(m, BASE7, SHOCK, WINDOW, labels=("baseline", FOCUS))

# %%
def product_table(frames, w0):
    post = lambda k: frames.get(("product", k), pd.DataFrame())
    dem, ful = post("demand"), post("fulfillment")
    t = pd.DataFrame({"demand": dem[dem.index >= w0].sum(), "delivered": ful[ful.index >= w0].sum(),
                      "lost units": post("lost_units")[lambda d: d.index >= w0].sum(),
                      "peak backlog": post("backlog")[lambda d: d.index >= w0].max()})
    t["fill rate %"] = 100 * t["delivered"] / t["demand"].replace(0, np.nan)
    return t.rename_axis("product")


if RUN_LOCAL:
    pb, ps = product_table(BASE7, W0), product_table(SHOCK, W0)
    hurt = pd.DataFrame({
        "materials hit": [", ".join(sorted(set(BOM.material_id[BOM.product_id == p]) & direct)) for p in pb.index],
        "fill rate % · base": pb["fill rate %"], "fill rate % · outage": ps["fill rate %"],
        "Δ delivered": ps["delivered"] - pb["delivered"], "Δ lost units": ps["lost units"] - pb["lost units"],
        "Δ peak backlog": ps["peak backlog"] - pb["peak backlog"],
    }).sort_values("Δ lost units", ascending=False)
    display(styled(capped(hurt, "products"), shade=["Δ lost units"],
                   fmt={"fill rate % · base": "{:.1f}", "fill rate % · outage": "{:.1f}", "Δ delivered": "{:+,.0f}",
                        "Δ lost units": "{:+,.0f}", "Δ peak backlog": "{:+,.0f}"},
                   caption=f"Products under {FOCUS} — seed {SEED7}"))
    worst = list(hurt.index[:4])
    fig, axes = plt.subplots(1, len(worst), figsize=(min(3.4 * len(worst), 13), 2.8), squeeze=False)
    for ax, p in zip(axes[0], worst):
        ax.plot(SHOCK[("product", "demand")][p], color=COLORS["orders"], linewidth=1.2, label="demand")
        ax.plot(BASE7[("product", "fulfillment")][p], color=COLORS["base"], linewidth=1.6, label="delivered · base")
        ax.plot(SHOCK[("product", "fulfillment")][p], color=COLORS["shock"], linewidth=1.6, label="delivered · outage")
        marks(ax, WINDOW, W0, legend=False)
        ax.set_title(p, fontsize=10)
        ax.set_xlabel("week")
    axes[0, 0].legend(fontsize=8, frameon=False)
    plt.tight_layout()
    plt.show()

# %% [markdown]
# **Reading it.** Start at the material that ran out first and read backwards. Stock falling while orders
# stay flat: the policy is not reacting. Orders rising while nothing arrives: the supply is not answering.
# A material the outage did not hit, used less: production stopped for want of another one, and its
# stock piles up. To tell the chain from the seed, set `INSPECTION_SEED` to another seed and run steps 5
# and 7 again: a stockout that stays in the same week is structural.

# %% [markdown]
# ## 8 · Export, and what produced these numbers
# Anyone with access to the project gets the same numbers from the same versions and seeds.
# **Expect:** the record, and the workbook written (in Colab, downloaded).

# %%
if RUN_LOCAL:
    record = pd.Series({
        "project": f"{project['name']} ({PID})", "supply chain model": PROJECT_MODEL,
        "dataset version": f"{data.id} · v{data.version_no} · graph_hash {data.graph_hash}",
        "policy version": f"{pol.label} ({pol.id}) · policy_hash {pol.policy_hash}",
        "scenario": f"{scenario['name']} ({scenario.get('id')})",
        "frame": f"{FRAME.get('horizon_days')} days · {FRAME.get('replications')} replications · seed "
                 f"{FRAME.get('seed')} · warm-up week {WARMUP}",
        "material-trace seeds": f"step 5: {SEED5} · step 7: {SEED7}", "engine": base["run"].get("code_version"),
        "computed by": "this machine (client)",
    }, name="value")
    display(record.to_frame())
    if EXPORT_XLSX:
        long = pd.concat([df.rename_axis("week").reset_index().melt(id_vars="week", var_name="item", value_name="value")
                          .assign(world=world, kind=kind, measure=measure)
                          for world, frames in ((f"baseline · seed {SEED5}", BASE), (f"baseline · seed {SEED7}", BASE7),
                                                (f"{FOCUS} · seed {SEED7}", SHOCK)) for (kind, measure), df in frames.items()])
        sheet = lambda s: "".join("_" if ch in "[]:*?/\\" else ch for ch in s)[:31]
        with pd.ExcelWriter(EXPORT_XLSX) as xw:
            record.to_frame().to_excel(xw, sheet_name="record")
            check.to_excel(xw, sheet_name="data check", index=False)
            kpi_table(base["run"]).to_excel(xw, sheet_name="baseline KPIs")
            mt.to_excel(xw, sheet_name="materials (baseline)")
            impact.to_excel(xw, sheet_name="disruption impact")
            touched.to_excel(xw, sheet_name=sheet(f"materials · {FOCUS}"))
            hurt.to_excel(xw, sheet_name=sheet(f"products · {FOCUS}"))
        long.to_csv(EXPORT_XLSX.rsplit(".", 1)[0] + "_weekly_items.csv", index=False)
        print("written:", EXPORT_XLSX, "and", EXPORT_XLSX.rsplit(".", 1)[0] + "_weekly_items.csv")
        try:
            from google.colab import files
            files.download(EXPORT_XLSX)
        except ImportError:
            pass

# %% [markdown]
# ## 9 · (Optional) The same baseline on the platform
# With `VERIFY_ON_PLATFORM = True` and a key with `write:runs`, the platform runs the baseline too and the
# two are compared KPI by KPI. It needs a saved policy version and a saved scenario, and uses your quota.
# **Expect:** `identical on every KPI: True`.

# %%
if VERIFY_ON_PLATFORM and RUN_LOCAL:
    if not (can("write:runs") and can("read:runs")):
        print("skipped: the key has no write:runs")
    elif pol.policy_hash is None or scenario.get("id") is None:
        print("skipped: the platform runs a SAVED policy version and a SAVED scenario — this study used "
              + ("policies rebuilt from /policies" if pol.policy_hash is None else "the Simulation Lab's defaults"))
    elif REPLICATIONS and REPLICATIONS != scenario.get("replications"):
        print("skipped: REPLICATIONS differs from the scenario's, so the two runs would not be the same run")
    else:
        platform = api.run_and_wait(PID, scenario["id"], pol.id, acknowledge_warnings=ACKNOWLEDGE_WARNINGS)
        keys = [k for k, v in (platform.get("aggregate_kpis") or {}).items() if isinstance(v, (int, float)) and not k.startswith("_")]
        same = all(platform["aggregate_kpis"][k] == base["run"]["aggregate_kpis"].get(k) for k in keys)
        print("identical on every KPI:", same)
        if not same:
            print("platform data", platform.get("dataset_version_id"), "vs this study's", data.id,
                  "· engines", platform.get("code_version"), "vs", base["run"].get("code_version"))
        display(pd.DataFrame({"platform": {kpi_label(k): fmt_kpi(k, platform["aggregate_kpis"][k]) for k in keys},
                              "this machine": {kpi_label(k): fmt_kpi(k, base["run"]["aggregate_kpis"].get(k)) for k in keys}}))

# %% [markdown]
# ## Next
# - **02** — the same outages as platform runs, saved where the Simulation Lab shows them.
# - **03** — fix what you found on a local copy first: a second supplier lane, more safety stock.
