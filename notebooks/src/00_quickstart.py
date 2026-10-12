# %% [markdown]
# # SuReSuite 00 · Quickstart
#
# **You will:** connect, run one simulation of a project, and read its results.
# **Time:** about 10 minutes. **You need:** nothing — without an API key the
# notebook runs in **demo mode** on a small example project.
#
# **To use your own project:** create a key on the app's **/developer** page, then
# - **Colab:** Secrets panel (key icon, left) → add `SURESUITE_API_KEY` → allow this notebook;
# - **local Jupyter:** `pip install jupyterlab requests pandas matplotlib pyarrow openpyxl`,
#   then `export SURESUITE_API_KEY="sk_test_…"` before `jupyter lab`.
#
# The key needs the scopes `read:data`, `read:policies`, `read:runs` and `write:runs`
# to run on the platform — plus `write:policies` when the project has no saved policy
# version yet, and `write:data` to freeze a dataset checkpoint (optional).
#
# Never paste a key into a cell. Run the cells in order (Runtime → Run all works too).

# %% include: config

# %% include: setup

# %% include: library

# %% include: demo_data baseline

# %%
api = connect(BASE_URL, API_KEY, DEMO_DATA)

# %% [markdown]
# ## 1 · Pick a project
# **Expect:** your projects as a table, then the one this notebook will use.
# To choose another, put its id in `PROJECT_ID` in the CONFIG cell.

# %%
display(pd.DataFrame(api.projects())[["id", "name", "plant_name", "created_at"]])
project = pick_project(api, PROJECT_ID)
PID = project["id"]

# %% [markdown]
# ## 2 · Freeze the input data and the policies
# A run always uses a frozen copy of the data and of the policies, so its result
# can be reproduced. Freezing twice without changes returns the same version.
# The run records the data it read by itself; freezing the data here only names
# that checkpoint, so a key without `write:data` skips it.
# **Expect:** a dataset version and a policy version, each with a hash.

# %%
VERSION = (next((v for v in api.policy_versions(PID) if v["id"] == POLICY_VERSION_ID), None)
           if POLICY_VERSION_ID else api.snapshot_policies(PID, "notebook baseline"))
if VERSION is None:
    raise SystemExit(f"POLICY_VERSION_ID {POLICY_VERSION_ID} is not a policy version of project {PID} "
                     "— set it to \"\" in the CONFIG cell to snapshot the current policies")
print("policy version ", VERSION["id"], "· policy_hash", VERSION["policy_hash"][:12])
try:
    frozen = api.freeze_dataset(PID, "notebook checkpoint")
    print("dataset version", frozen["id"], "· graph_hash", frozen["graph_hash"][:12])
except SuReSuiteError as e:
    if e.code != "missing_scope":
        raise
    print("dataset not frozen here (this key has no write:data scope) — the run records the data it reads")

# %% [markdown]
# ## 3 · Choose a baseline scenario
# Uses `SCENARIO_ID` if set, otherwise the newest scenario without disruptions,
# otherwise creates one (52 weeks, 10 replications, seed 42).
# **Expect:** one line describing the scenario.

# %%
scenario = baseline_scenario(api, PID, SCENARIO_ID)

# %% [markdown]
# ## 4 · Run it
# The run happens on the platform; this cell waits for it. Running the cell again
# returns the same run rather than paying for a new one.
# **Expect:** `→ done` and the number of replications.

# %%
run = api.run_and_wait(PID, scenario["id"], VERSION["id"])

# %% [markdown]
# ## 5 · Read the results
# **Expect:** each KPI's mean over the replications and its 95 % confidence interval.

# %%
kpi_table(run).drop(columns="value")

# %% [markdown]
# **Expect:** one row per replication. Replications differ only in their random draws.

# %%
reps = replications_frame(api.replications(run["id"]))
reps[[c for c in ("fill_rate", "revenue", "lost_sales_value", "avg_on_hand_value") if c in reps]].round(2)

# %% [markdown]
# **Expect:** a chart of material on hand per week — the line is the average, the
# band the range across replications.

# %%
weekly = api.series(run["id"])
plot_series({"baseline": weekly}, "on_hand_units", title="Material on hand (units), weekly")

# %% [markdown]
# ## 6 · Check how much to trust it
# **Expect:** `unvalidated` unless someone validated this model in the app
# (/policies → Run & Validate).

# %%
print("credibility:", api.validation(run["id"])["status"])

# %% [markdown]
# ## Next
# - **01** — change a policy and measure the effect.
# - **02** — test disruptions (plant shutdown, supplier outage).
# - **03** — run the engine on your own machine.
#
# Uploading data, network analysis and model validation are done in the app.
