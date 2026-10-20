# %% [markdown]
# # SuReSuite 05 · Available to promise
#
# **You will:** answer a request the way a planner does: *can we give this customer Q units of a
# product, or Q units of a material from stock, by this date?* The notebook checks the stock position,
# plays the request through your own supply chain (your data, the policies as they are on /policies
# now, supplier and production lead times, plant capacity, every existing customer's demand), and
# answers yes, or how much by then and when the rest, or a nearby date that works (pull in or push back).
# **Time:** about 10 minutes (on a large project, a few minutes per candidate date).
# **You need:** nothing for demo mode; with a key, `read:data` and `read:policies` (`read:runs` to use your
# saved scenario's horizon). Every user can create that key on /developer.
#
# Nothing here changes your project. The request is added to a **copy** of your data on this machine.
#
# **How a promise is decided.** Your chain is run in `N_WORLDS` possible futures (one random seed each),
# with and without the request, on the same draws. A week is promised when, in at least `CONFIDENCE` of
# those futures, the request is complete by then; what it costs existing customers is reported beside it,
# because an order can be on time and still take material someone else needed later. A make-to-order
# request is served after every existing customer row (`SERVE_LAST`), which is what "available to promise"
# means. And it is answered twice: with your materials replenished **as your policies are**, and with the
# request's materials **planned from the order book** (MRP: ordered one lead time ahead of the need), so
# you see what accepting the order and telling purchasing now would change.

# %% include: config

# %% include: setup

# %% include: library

# %% include: local

# %% include: study

# %% include: demo_data baseline

# %% [markdown]
# ## Try changing
# - `REQUEST_KIND` — `"product"`: a customer's make-to-order request; `"material"`: material taken from stock.
# - `ITEM_ID`, `QUANTITY`, `NEEDED_BY` (a date) or `NEEDED_WEEK` — what, how many, by when.
# - `CONFIDENCE` — promise only what holds in at least this share of futures; `N_WORLDS` — how many futures.
# - `SEARCH_WEEKS` — how far each way to look for a pull-in or a push-back.
# - `DELIVERY_WEEKS` — transit to the customer, which the engine does not model; `None` reads your customer lanes.
# - `PLAN_MATERIALS` — answer with your replenishment as it is, with the request's materials planned from the order book, or both.

# %%
REQUEST_KIND = "product"     # "product" | "material"
ITEM_ID = ""                 # a product or material id; "" = the first product (or material) in your data
QUANTITY = 150
NEEDED_BY = ""               # "YYYY-MM-DD"; "" = NEEDED_WEEK
NEEDED_WEEK = 20             # weeks from week 0 (START_DATE)
START_DATE = ""              # the date of week 0; "" = your earliest forecast period, else today
DELIVERY_WEEKS = None        # product only: weeks in transit to the customer; None = the product's lanes
CONFIDENCE = 0.9
N_WORLDS = 10
SEARCH_WEEKS = 3
SERVE_LAST = True            # product only: True = after every existing customer row; False = your allocation rule
PLAN_MATERIALS = "both"      # product only: "as is" | "order book" (MRP for the request's materials) | "both"
DATA_SOURCE = "current"      # "current" | "latest" | a dataset version id
POLICY_SOURCE = "current"    # "current" | "pinned" (POLICY_VERSION_ID exactly)
MAX_ROWS = 40
EXPORT_XLSX = "available_to_promise.xlsx"   # "" = no export

# %% [markdown]
# ## 1 · Connect, load the data and the policies
# The same reading as notebook 04: the data a run reads (frozen now, or the newest frozen copy and its
# age), the policies as they are on /policies now, and your saved baseline scenario's horizon.
# **Expect:** your project, what the key allows, the data and policy versions used, and the scenario.

# %%
import matplotlib.ticker as mticker
from IPython.display import Markdown

api = connect(BASE_URL, API_KEY, DEMO_DATA, needs=["read:data", "read:policies"], mode=MODE)
LIVE = api.live
project = pick_project(api, PROJECT_ID)
PID = project["id"]
PROJECT_MODEL = project.get("supply_chain_model")
SCOPES = key_scopes(api)
display(key_table(SCOPES, verify_use="(not used here)"))

data = load_dataset(api, PID, DATA_SOURCE, SCOPES, LIVE, "notebook 05")
print(data)
pol, drift, now_fam = load_policies(api, PID, POLICY_SOURCE, POLICY_VERSION_ID, SCOPES, "notebook 05")
if len(drift):
    display(styled(capped(drift, "differences"), caption="Saved version vs /policies now"))
scenario, FRAME, _ = study_scenario(api, PID, SCENARIO_ID, SCOPES)
RUN_LOCAL = ensure_engine(api, LIVE)
if not RUN_LOCAL:
    raise Stop("this notebook plays the request through the engine — add SURESUITE_API_KEY and run all cells again")

T = input_tables(data)
BOM = flat_bom(T)
lanes = supply_lanes(T)
FRAME_ALL = {**scenario, **FRAME}
EV = engine_view(data, pol, FRAME_ALL, PROJECT_MODEL)  # what the engine receives: lead times, capacities, stock
NET = EV["network"]
H = int(round(float(FRAME_ALL.get("horizon_days") or 364) / 7))

# %% [markdown]
# ## 2 · The request, in the engine's weeks
# Week 0 is the start of the simulation: your opening stock as it is in the data. Lead times and capacities
# below are what the engine received, not a second reading of your tables.
# **Expect:** the request, the week it falls in, and every lead time that stands between it and delivery.

# %%
def to_date(week):
    return (START + pd.Timedelta(weeks=int(week))).date()


fc = T["demand_forecasts"]
START = pd.Timestamp(START_DATE) if START_DATE else (
    pd.to_datetime(col(fc, "period_start")).min() if len(fc) else pd.Timestamp.today().normalize())
if pd.isna(START):
    START = pd.Timestamp.today().normalize()
NEED_WEEK = int((pd.Timestamp(NEEDED_BY) - START).days // 7) if NEEDED_BY else int(NEEDED_WEEK)

products = {p["id"]: p for p in NET["products"]}
materials = {m["id"]: m for m in NET["materials"]}
links = pd.DataFrame(NET["supplier_links"])
suppliers = {s["id"]: s for s in NET["suppliers"]}
ITEM = ITEM_ID or (next(iter(products)) if REQUEST_KIND == "product" else next(iter(materials)))
if ITEM not in (products if REQUEST_KIND == "product" else materials):
    raise Stop(f"{ITEM!r} is not a {REQUEST_KIND} the engine received — check ITEM_ID against your data")


def lead_weeks(material):
    """The material's replenishment lead time in weeks: its primary supplier link's, else the shortest."""
    ls = links[links.material_id == material]
    if ls.empty:
        return None
    primary = ls[ls["primary"] == True]  # noqa: E712 — a column of booleans
    return int((primary if len(primary) else ls)["lead_time_weeks"].min())


if REQUEST_KIND == "product":
    if DELIVERY_WEEKS is not None:
        TRANSIT = int(DELIVERY_WEEKS)
    else:
        ob = T["outbound"]
        lt = pd.to_numeric(col(ob[col(ob, "product_id").astype(str) == ITEM], "expected_lead_time"), errors="coerce").dropna()
        TRANSIT = int(round(lt.median())) if len(lt) else 0
    SHIP_WEEK = NEED_WEEK - TRANSIT
    need = BOM[BOM.product_id == ITEM].assign(needed=lambda d: d.rate * QUANTITY)
    p = products[ITEM]
    facts = {
        "request": f"{QUANTITY:,.0f} × {ITEM} ({p.get('name') or ''})", "needed by": f"{to_date(NEED_WEEK)} (week {NEED_WEEK})",
        "transit to customer": f"{TRANSIT} wk → ship by week {SHIP_WEEK} ({to_date(SHIP_WEEK)})",
        "made": str(p.get("fulfillment_mode")).upper(), "plant capacity": f"{p.get('production_capacity'):,.0f} / wk",
        "production lead time": f"{p.get('production_lead_time_weeks') or 0:g} wk",
    }
    display(pd.Series(facts, name="").to_frame())
    MATS = list(need.material_id)
    display(styled(need.set_index("material_id").assign(
        **{"lead time (wk)": [lead_weeks(m) for m in need.material_id],
           "opening stock": [materials.get(m, {}).get("initial_on_hand") for m in need.material_id],
           "suppliers": [", ".join(sorted(links.supplier_id[links.material_id == m])) or "—" for m in need.material_id]}
    )[["rate", "needed", "opening stock", "lead time (wk)", "suppliers"]],
        fmt={"rate": "{:g}", "needed": "{:,.0f}", "opening stock": "{:,.0f}"},
        caption="What the request needs from each material"))
else:
    SHIP_WEEK = NEED_WEEK
    MATS = [ITEM]
    m = materials[ITEM]
    display(pd.Series({
        "request": f"{QUANTITY:,.0f} × {ITEM} ({m.get('name') or ''}) from stock",
        "needed by": f"{to_date(NEED_WEEK)} (week {NEED_WEEK})", "opening stock": f"{m.get('initial_on_hand') or 0:,.0f}",
        "replenishment lead time": f"{lead_weeks(ITEM)} wk",
        "suppliers": ", ".join(sorted(links.supplier_id[links.material_id == ITEM])) or "—",
    }, name="").to_frame())
if not 0 <= SHIP_WEEK < H:
    raise Stop(f"the request falls in week {SHIP_WEEK}, outside the simulated weeks 0–{H - 1}")
print("note: the data holds no open purchase orders, so the first lead-time weeks can understate supply you "
      "have already ordered.")

# %% [markdown]
# ## 3 · Stock position: what you hold, what is coming, what is free
# The project as it is, in `N_WORLDS` futures. **Available to promise** at a week is what you can take
# out then without running short before a reorder can arrive: the lowest stock between that week and one
# lead time later, at the `CONFIDENCE` level across futures.
# **Expect:** a table per material at the needed week, and a chart of each material's stock and its ATP.

# %%
SEEDS = [int(FRAME_ALL.get("seed", 42)) + i for i in range(N_WORLDS)]
started = time.time()
WORLDS = {s: inspect_run(data, pol, FRAME_ALL, PROJECT_MODEL, s)[1] for s in SEEDS}
ONE_RUN = (time.time() - started) / len(SEEDS)
print(f"{len(SEEDS)} futures in {time.time() - started:.1f}s")


def stock(frames_by_seed, material, measure="on_hand"):
    """weeks × seeds for one material."""
    return pd.DataFrame({s: f[("material", measure)][material] for s, f in frames_by_seed.items()})


def free_stock(oh, lead):
    """For each week, the lowest stock from that week to one lead time later — what can leave then."""
    return pd.DataFrame({w: oh.iloc[w:min(w + lead, len(oh) - 1) + 1].min() for w in oh.index}).T


q = 1 - CONFIDENCE
pos = []
for m in MATS:
    oh, lt = stock(WORLDS, m), lead_weeks(m) or 2
    atp = free_stock(oh, lt).quantile(q, axis=1)
    use = pd.DataFrame({s: use_of(f, BOM)[m] for s, f in WORLDS.items()})
    pos.append({"material": m, "opening stock": materials.get(m, {}).get("initial_on_hand"),
                f"on hand wk {SHIP_WEEK} (median)": oh.loc[SHIP_WEEK].median(),
                f"on hand wk {SHIP_WEEK} (low, {q:.0%})": oh.loc[SHIP_WEEK].quantile(q),
                "in transit (median)": stock(WORLDS, m, "in_transit").loc[SHIP_WEEK].median(),
                "use / wk": use.mean().mean(), "lead time (wk)": lt,
                f"ATP wk {SHIP_WEEK}": atp.loc[SHIP_WEEK]})
POSITION = pd.DataFrame(pos).set_index("material")
display(styled(POSITION, fmt={c: "{:,.0f}" for c in POSITION.columns if c != "lead time (wk)"},
               shade=[f"ATP wk {SHIP_WEEK}"], cmap="Greens",
               caption=f"Stock position at week {SHIP_WEEK} ({to_date(SHIP_WEEK)}) — ATP at {CONFIDENCE:.0%} confidence"))

for m in MATS[:4]:
    oh, lt = stock(WORLDS, m), lead_weeks(m) or 2
    atp = free_stock(oh, lt).quantile(q, axis=1)
    fig, ax = plt.subplots(figsize=(11, 3.2))
    ax.fill_between(oh.index, oh.quantile(0.1, axis=1), oh.quantile(0.9, axis=1), color="#2a78d6", alpha=0.15,
                    linewidth=0, label="on hand, 10th–90th percentile")
    ax.plot(oh.index, oh.median(axis=1), color="#2a78d6", linewidth=1.8, label="on hand, median")
    ax.step(atp.index, atp.values, where="post", color="#008300", linewidth=1.8, label=f"available to promise ({CONFIDENCE:.0%})")
    want = QUANTITY if REQUEST_KIND == "material" else float(need.set_index("material_id").loc[m, "needed"])
    ax.scatter([SHIP_WEEK], [want], color="#d9480f", zorder=5, s=40, label=f"request: {want:,.0f} in week {SHIP_WEEK}")
    ax.axvline(SHIP_WEEK, color="#d9480f", linewidth=0.8, linestyle=":")
    ax.set_title(f"{m} — lead time {lt} wk", fontsize=10)
    ax.set_xlabel("week")
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(fontsize=8, frameon=False, loc="upper left", bbox_to_anchor=(1.01, 1.0))
    plt.tight_layout()
    plt.show()

# %% [markdown]
# ## 4 · Play the request through the chain
# **A product:** the request becomes a firm order from a customer row added to a copy of your data
# (`ATP-REQUEST`), in the ship week, waiting if it cannot be met at once. The same futures are run with the
# row ordering nothing, so the only difference is the order. Every candidate week from `SEARCH_WEEKS` before
# to `SEARCH_WEEKS` after is tried, which is what a pull-in or push-back would be. The request's deliveries
# are the product's extra deliveries plus what existing customers of the product lost to it (served last,
# they lose only to material or capacity the request used earlier).
# **A material:** the engine has no way to take material out of stock directly, so the answer is read from
# step 3's stock: the request fits a week when stock stays above it until a reorder can arrive.
# **Expect:** the time it will take, then one row per candidate week.

# %%
WEEKS = [w for w in range(SHIP_WEEK - SEARCH_WEEKS, SHIP_WEEK + SEARCH_WEEKS + 1) if 0 <= w < H]
TOL = max(0.5, 0.001 * QUANTITY)

def candidate_row(w, delivered, harm):
    """One candidate week from per-future results: delivered (weeks × futures, capped at the
    quantity) and harm (units existing customers lost, per future)."""
    done = delivered.ge(QUANTITY - TOL)
    when = done.apply(lambda c: c[c.index >= w].idxmax() if c[c.index >= w].any() else np.nan)
    return {"week": w, "date": to_date(w), "on time": (when <= w).mean(),
            f"on time at {CONFIDENCE:.0%}": delivered.loc[w].quantile(q),
            f"complete by (at {CONFIDENCE:.0%})": when.quantile(CONFIDENCE, interpolation="higher")
            if when.notna().mean() >= CONFIDENCE else np.nan,
            "others lose (median)": harm.median() if harm is not None else np.nan}


CANDS, TRIALS, ZEROS, SPLITS = {}, {}, {}, {}
if REQUEST_KIND == "product":
    REQ = "ATP-REQUEST"
    rule = (EV["policies"].get("customer_allocation") or {}).get("rule")
    ic = EV["policies"].get("inventory_control") or {}
    mrp_already = all(((ic.get("material_overrides") or {}).get(m) or {}).get("policy_type", ic.get("policy_type")) == "mrp"
                      for m in MATS)
    MODES = {"as is": False, "order book": True}
    MODES = {k: v for k, v in MODES.items() if PLAN_MATERIALS in (k, "both")}
    if mrp_already and "order book" in MODES:
        print("the request's materials already plan from the order book (MRP) — one answer covers both")
        MODES = {"as is": False}
    ob = T["outbound"]
    row = {"customer_id": REQ, "product_id": ITEM, "volume": 1e-6, "time_unit": "week",
           "unit_price": products[ITEM].get("unit_price"), "expected_lead_time": TRANSIT}
    data_req = with_tables(data, outbound=pd.concat([ob, pd.DataFrame([row])], ignore_index=True))

    def with_order(schedule, order_book=False):
        """The policy copy with the request row's firm delivery schedule (units per week from week 0,
        waiting if unmet) and, for `order_book`, the request's materials planned by MRP on every lane
        that supplies them."""
        snap = copy.deepcopy(pol.snapshot)
        over = snap.setdefault("overrides", [])
        patch = {"backorder_allowed": True, "max_backorder_days": 182}
        if SERVE_LAST:
            patch["row_priority"] = 0
            if rule not in ("priority", "sla_tier"):
                snap.setdefault("defaults", {}).setdefault("fulfillment", {})["allocation"] = "priority"
        over.extend([
            {"scope": "node", "target_key": f"{REQ}::{ITEM}", "family": "demand",
             "patch": {"row_demand_schedule": [float(x) for x in schedule]}},
            {"scope": "node", "target_key": f"{REQ}::{ITEM}", "family": "fulfillment", "patch": patch}])
        if order_book:
            for sup, mat in links[links.material_id.isin(MATS)][["supplier_id", "material_id"]].itertuples(index=False):
                key = f"{sup}::{mat}"
                hit = next((o for o in over if o.get("target_key") == key and o.get("family") == "inventory"), None)
                if hit:
                    hit["patch"] = {**(hit.get("patch") or {}), "type": "mrp"}
                else:
                    over.append({"scope": "node", "target_key": key, "family": "inventory", "patch": {"type": "mrp"}})
        return Policy(id=pol.id, policy_hash=None, snapshot=snap, label="with the request")

    if SERVE_LAST and rule not in ("priority", "sla_tier"):
        print(f"your allocation rule is {rule or 'the engine default'}; for this check the request is served after "
              "every existing row (priority rule, the request last) — both sides of the comparison use it")
    n_runs = len(SEEDS) * (len(WEEKS) + 2) * len(MODES)
    print(f"{n_runs} one-replication runs — about {ONE_RUN * n_runs:.0f}s")
    for mode, order_book in MODES.items():
        ZEROS[mode] = zero = {s: inspect_run(data_req, with_order([0.0], order_book), FRAME_ALL, PROJECT_MODEL, s)[1]
                              for s in SEEDS}

        def delivered(f, s, zero=zero):
            """Units delivered to the request by each week: the product's extra deliveries plus what its
            existing customers lost to it, capped at the quantity."""
            dF = (f[("product", "fulfillment")][ITEM] - zero[s][("product", "fulfillment")][ITEM]).cumsum()
            dL = (f[("product", "lost_units")][ITEM] - zero[s][("product", "lost_units")][ITEM]).cumsum()
            return (dF + dL).clip(upper=QUANTITY)

        rows, TRIALS[mode] = [], {}
        for w in WEEKS:
            worlds = {s: inspect_run(data_req, with_order([0.0] * w + [QUANTITY], order_book), FRAME_ALL,
                                     PROJECT_MODEL, s)[1] for s in SEEDS}
            TRIALS[mode][w] = worlds
            harm = pd.Series({s: max(0.0, sum((f[("product", "lost_units")][p] - zero[s][("product", "lost_units")][p]).sum()
                                              for p in f[("product", "lost_units")].columns)) for s, f in worlds.items()})
            rows.append(candidate_row(w, pd.DataFrame({s: delivered(f, s) for s, f in worlds.items()}), harm))
        CANDS[mode] = pd.DataFrame(rows).set_index("week")

        # A split delivery, when the plant cannot make it all in one week: equal parts in the weeks up to
        # the wanted one, as many as the capacity existing customers leave free requires.
        cap = products[ITEM].get("production_capacity") or np.inf
        spare = pd.Series({s: cap - f[("product", "production")][ITEM].loc[SHIP_WEEK] for s, f in zero.items()}).quantile(q)
        if CANDS[mode].loc[SHIP_WEEK, "on time"] < CONFIDENCE and 0 < spare < QUANTITY:
            k = min(int(np.ceil(QUANTITY / spare)), SHIP_WEEK + 1, SEARCH_WEEKS + 1)
            plan = [0.0] * (SHIP_WEEK - k + 1) + [QUANTITY / k] * k
            worlds = {s: inspect_run(data_req, with_order(plan, order_book), FRAME_ALL, PROJECT_MODEL, s)[1] for s in SEEDS}
            got = pd.DataFrame({s: delivered(f, s) for s, f in worlds.items()})
            SPLITS[mode] = {"parts": k, "each": QUANTITY / k, "from": SHIP_WEEK - k + 1,
                            "on time": got.loc[SHIP_WEEK].ge(QUANTITY - TOL).mean()}
else:
    oh, lt = stock(WORLDS, ITEM), lead_weeks(ITEM) or 2
    free = free_stock(oh, lt).clip(upper=QUANTITY)
    CANDS["from stock"] = pd.DataFrame([candidate_row(w, free, None) for w in range(H)]).set_index("week")

for mode, cand in CANDS.items():
    shown = cand.loc[[w for w in WEEKS if w in cand.index]]
    display(styled(shown.assign(**{"on time": shown["on time"] * 100}).rename(columns={"on time": "on time (% of futures)"}),
                   fmt={"on time (% of futures)": "{:.0f}", f"on time at {CONFIDENCE:.0%}": "{:,.0f}",
                        f"complete by (at {CONFIDENCE:.0%})": "{:.0f}", "others lose (median)": "{:,.0f}"},
                   shade=["on time (% of futures)"], cmap="Greens",
                   caption=f"{QUANTITY:,.0f} × {ITEM}, wanted in week {SHIP_WEEK} — materials {mode}"))

# %% [markdown]
# ## 5 · The answer
# **Expect:** yes, or how much on time and when the rest, and the nearest week each way that works.

# %%
def week_text(w):
    return f"week {int(w)} ({to_date(int(w))})"


what = "ship" if REQUEST_KIND == "product" else "issue"


def answer(cand, mode):
    """The planner's answer for one way of replenishing: yes, or partial + when, pull in, push back."""
    at = cand.loc[SHIP_WEEK]
    ok_weeks = [w for w in cand.index if cand.loc[w, "on time"] >= CONFIDENCE]
    pull = max([w for w in ok_weeks if w < SHIP_WEEK], default=None)
    push = min([w for w in ok_weeks if w > SHIP_WEEK], default=None)
    on_time_qty, complete = at[f"on time at {CONFIDENCE:.0%}"], at[f"complete by (at {CONFIDENCE:.0%})"]
    harm = at["others lose (median)"]
    cost = (f" Existing customers lose a median **{harm:,.0f}** units to it." if harm >= TOL else
            " Existing customers lose nothing to it.") if harm == harm else ""
    out = [f"#### Materials {mode}"]
    if at["on time"] >= CONFIDENCE:
        out.append(f"**Yes — promise it.** Complete by {week_text(SHIP_WEEK)} in {at['on time']:.0%} of futures.{cost}")
        if pull is not None:
            out.append(f"- It could even {what} from {week_text(pull)} (pull in).")
    else:
        out.append(f"**Not all of it on time** — complete by then in {at['on time']:.0%} of futures (the bar is "
                   f"{CONFIDENCE:.0%}).{cost}")
        if on_time_qty >= TOL:
            out.append(f"- **Partial:** {on_time_qty:,.0f} by {week_text(SHIP_WEEK)}, the remaining "
                       f"{QUANTITY - on_time_qty:,.0f} by " + (f"{week_text(complete)}." if complete == complete else
                                                               "a date beyond the horizon at this confidence."))
        later = push if push is not None else (complete if complete == complete else None)
        if later is not None:
            out.append(f"- **Push back:** all of it by {week_text(later)}.")
        if pull is not None:
            out.append(f"- **Pull in:** all of it by {week_text(pull)}, before the capacity or stock it needs is taken.")
        split = SPLITS.get(mode)
        if split:
            out.append(f"- **Split:** {split['parts']} deliveries of {split['each']:,.0f}, weeks {split['from']}–{SHIP_WEEK} "
                       f"(the first on {to_date(split['from'])}) — complete on time in {split['on time']:.0%} of futures. "
                       "The plant cannot make it all in one week beside existing orders.")
        if later is None and pull is None and not split:
            out.append("- **No week within the horizon works at this confidence.**")
        if REQUEST_KIND == "material":
            sup = links[links.material_id == ITEM].sort_values("lead_time_weeks").iloc[0]["supplier_id"]
            spare = suppliers[sup]["capacity_per_week"] - lanes[lanes.supplier_id == sup]["per_week"].sum()
            out.append(f"- **Order it:** a new order from {sup} placed now arrives about {week_text(lead_weeks(ITEM))} "
                       f"({sup}'s spare capacity is about {max(spare, 0):,.0f} / week).")
    return out


head = f"### {QUANTITY:,.0f} × {ITEM}, wanted {week_text(SHIP_WEEK)}" + (
    f" — at the customer {to_date(NEED_WEEK)}" if REQUEST_KIND == "product" else "")
answers = {mode: answer(cand, mode) for mode, cand in CANDS.items()}
if len(answers) == 2 and len({tuple(a[1:]) for a in answers.values()}) == 1:
    body = next(iter(answers.values()))[1:] + ["", "*The same either way: planning the request's materials from the "
                                               "order book changes nothing here — material is not what limits it.*"]
else:
    body = [line for a in answers.values() for line in a]
display(Markdown("\n".join([head] + body)))

span = WEEKS if REQUEST_KIND == "product" else list(range(max(0, SHIP_WEEK - 8), min(H, SHIP_WEEK + 9)))
fig, axes = plt.subplots(1, 2, figsize=(11, 3.2))
width = 0.8 / len(CANDS)
for i, (mode, cand) in enumerate(CANDS.items()):
    x = np.array(span) + (i - (len(CANDS) - 1) / 2) * width
    color = ["#2a78d6", "#008300"][i % 2]
    axes[0].bar(x, cand.loc[span, "on time"] * 100, width=width, color=color, label=f"materials {mode}")
    axes[1].bar(x, cand.loc[span, f"on time at {CONFIDENCE:.0%}"], width=width, color=color, label=f"materials {mode}")
axes[0].axhline(CONFIDENCE * 100, color="#d9480f", linewidth=1, linestyle="--", label=f"bar: {CONFIDENCE:.0%}")
axes[0].set_title(f"Complete on time, by {what} week (% of futures)", fontsize=10)
axes[1].axhline(QUANTITY, color="#d9480f", linewidth=1, linestyle="--", label="requested")
axes[1].set_title(f"Units on time in that week ({CONFIDENCE:.0%} of futures)", fontsize=10)
for ax in axes:
    ax.axvline(SHIP_WEEK, color="#495057", linewidth=0.8, linestyle=":")
    ax.set_xlabel("week")
    ax.xaxis.set_major_locator(mticker.MaxNLocator(integer=True))
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(fontsize=8, frameon=False)
plt.tight_layout()
plt.show()

# %% [markdown]
# ## 6 · What stands in the way
# For a product request: how many units of it each constraint could cover in the wanted week — the plant's
# capacity left over by existing customers, and each material's stock at the start of the week (with the
# request in the books, so anything ordered for it counts) divided by what one unit uses. The smallest is
# what limits the on-time quantity.
# **Expect:** one table per way of replenishing, the binding constraint marked.

# %%
if REQUEST_KIND == "product":
    cap = products[ITEM].get("production_capacity") or np.nan
    rate = need.set_index("material_id")["rate"]
    start = max(SHIP_WEEK - 1, 0)
    for mode, zero in ZEROS.items():
        covers = {f"plant capacity ({cap:,.0f}/wk)": pd.Series(
            {s: cap - f[("product", "production")][ITEM].loc[SHIP_WEEK] for s, f in zero.items()})}
        for m in MATS:
            covers[f"{m} stock (lead time {lead_weeks(m)} wk)"] = pd.Series(
                {s: f[("material", "on_hand")][m].loc[start] / rate[m] for s, f in TRIALS[mode][SHIP_WEEK].items()})
        tab = pd.DataFrame({"covers (median)": {k: v.median() for k, v in covers.items()},
                            f"covers (low, {q:.0%})": {k: v.quantile(q) for k, v in covers.items()}})
        tab["short of the request by"] = (QUANTITY - tab[f"covers (low, {q:.0%})"]).clip(lower=0)
        tab["binds"] = np.where(tab[f"covers (low, {q:.0%})"] == tab[f"covers (low, {q:.0%})"].min(), "yes", "")
        display(styled(tab.rename_axis(f"week {SHIP_WEEK}"), fmt={c: "{:,.0f}" for c in tab.columns if c != "binds"},
                       shade=["short of the request by"],
                       caption=f"Materials {mode}: units of {ITEM} each constraint covers in week {SHIP_WEEK}"))
    print("a material's stock can be topped up within the week by deliveries already on the way, so it can cover a\n"
          "little more than shown; plant capacity cannot.")
else:
    print("a material request is limited by its own stock and lead time — see step 3")

# %% [markdown]
# **Reading it.** A request that only fails on plant capacity can often ship partly now and the rest a week
# later; one that fails on a material waits for that material's lead time, which is why its push-back date
# jumps. "Others lose" above zero means the request, even served last, used capacity or material an existing
# customer needed later: promising it is a choice, not a free answer. When the "order book" answer is better
# than "as is", the gap is purchasing not seeing the order: telling them now (or running those materials on
# MRP) is what closes it. Raise `N_WORLDS` before you quote a date that sits just above the bar.

# %% [markdown]
# ## 7 · Export, and what produced this answer
# **Expect:** the record, and the workbook written (in Colab, downloaded).

# %%
record = pd.Series({
    "project": f"{project['name']} ({PID})", "supply chain model": PROJECT_MODEL,
    "dataset version": f"{data.id} · v{data.version_no} · graph_hash {data.graph_hash}",
    "policy version": f"{pol.label} ({pol.id}) · policy_hash {pol.policy_hash}",
    "request": f"{REQUEST_KIND}: {QUANTITY:,.0f} × {ITEM}, week {SHIP_WEEK}"
               + (f" (+{TRANSIT} wk transit)" if REQUEST_KIND == "product" else ""),
    "week 0": str(START.date()), "futures": f"{len(SEEDS)} (seeds {SEEDS[0]}–{SEEDS[-1]}) · confidence {CONFIDENCE:.0%}",
    "served": ("after every existing row" if SERVE_LAST else "by the project's rule") if REQUEST_KIND == "product" else "from stock",
    "materials": ", ".join(CANDS),
    "computed by": "this machine (client)",
}, name="value")
display(record.to_frame())
if EXPORT_XLSX:
    with pd.ExcelWriter(EXPORT_XLSX) as xw:
        record.to_frame().to_excel(xw, sheet_name="record")
        POSITION.to_excel(xw, sheet_name="stock position")
        for mode, cand in CANDS.items():
            cand.to_excel(xw, sheet_name=f"weeks · materials {mode}"[:31])
    print("written:", EXPORT_XLSX)
    try:
        from google.colab import files
        files.download(EXPORT_XLSX)
    except ImportError:
        pass

# %% [markdown]
# ## Next
# - **04** — every material week by week, and what each supplier outage does to them.
# - **03** — try the fix on a local copy first: a second supplier lane, more safety stock, more capacity.
