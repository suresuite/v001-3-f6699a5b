# ACCURATE_Tron — Tronico dataset: parameters

Anonymized: every identifier is a pseudonym (PRD-/MAT-/SUP-/CUST-). Quantities, prices, costs, MOQs, lead times and BOM rates are the study's own values, unchanged.

**Size**: 17 products · 560 materials · 61 suppliers · 599 BOM rows · 635 inbound lanes · 17 outbound rows.

**Adjusted to engine limits**: 0 lane cost(s) floored at 0.0001, 0 lead time(s) clamped to 1..51 weeks, 0 safety-stock day value(s) clamped to 84, 0 primary-supplier override(s). Details: `audit.json`.

## Upload order (SuReSuite → Project Manager → Upload)

1. `suppliers.csv` (Suppliers Master) 2. `materials.csv` (Materials Master) 3. `products.csv` (Products Master) 4. `customers.csv` (Customers Master) 5. `bom_single_level.csv` (BOM Single Level) 6. `inbound_logistic.csv` (Inbound Logistics) 7. `outbound_logistic.csv` (Outbound Logistics).

## Fields

| File | Column | Unit | Source (workbook) | Rule |
|---|---|---|---|---|
| `suppliers.csv` | `supplier_id` | id | sourcingDT/supplierDT · Supplier number | pseudonym SUP-nnn; only suppliers with at least one usable lane |
| `suppliers.csv` | `name` | text | — | 'Supplier <id> (<country>)'; real names removed |
| `suppliers.csv` | `capacity_per_week` | units/wk | — | blank = unlimited (the study models disruptions as lead-time delays, not capacity) |
| `suppliers.csv` | `reliability_score` | 0..1 | — | 1.0 (the study has no stochastic supplier failure) |
| `materials.csv` | `material_id` | id | MaterialDT · Material number | pseudonym MAT-nnnn; only materials used by an in-scope product's BOM with a lane of lead time 0..53 wk (SupplyChainData filter) |
| `materials.csv` | `name` | text | MaterialDT · Category | '<id> — <generic English category>' |
| `materials.csv` | `cost` | €/unit | sourcingDT · Ordering cost (primary lane) | per-unit cost of the primary lane; 0 or blank floored at 0.0001 (engine needs > 0) |
| `materials.csv` | `holding_cost_pct` | share/yr | — | 0.20 (WSC 2026 Table 2) |
| `materials.csv` | `moq` | units | sourcingDT · MOQ (primary lane) | blank -> 0 (as the loader does) |
| `materials.csv` | `initial_on_hand` | units | derived | round(E[D_m] · T_s): the model's starting stock (SupplyChainSimulation.__post_init__) |
| `materials.csv` | `lead_time_dist / lead_time_cv` | — | — | deterministic / 0 (the study's lead times are fixed) |
| `products.csv` | `product_id / name` | id | ProductDT · Product | pseudonym PRD-nnn; the test article and the lumpy-demand article the loader excludes are dropped |
| `products.csv` | `sell_price` | €/unit | ProductDT · UnitPrice | unchanged |
| `products.csv` | `production_capacity` | units/wk | demandDT | SupplyChainData.product_capacity = ceil(0.9 × max weekly demand) — follows data_loader.py |
| `products.csv` | `fulfillment_mode` | — | — | mto (make-to-order) |
| `products.csv` | `demand_distribution` | — | — | triangular |
| `products.csv` | `demand_mean` | units/wk | demandDT | the triangular MODE b = median of non-zero weekly demand (SupplyChainSimulation.tri_params) |
| `products.csv` | `demand_cv` | fraction | — | 0.30 = the study's triangular_variation ν |
| `outbound_logistic.csv` | `demand_min / demand_max` | units/wk | demandDT | a = max(0, (1−ν)·b), c = historical max — the asymmetric triangular the study samples; carried on the customer row because the products CSV has no min/max columns |
| `outbound_logistic.csv` | `customer_id` | id | — | one aggregate customer CUST-001 per product (the study has no customer split) |
| `outbound_logistic.csv` | `volume / unit_price` | units/wk / € | ProductDT | b and UnitPrice |
| `bom_single_level.csv` | `consumption_rate` | units/unit | BOMDT · Consumption rate | rows with rate 0, or a product/material out of scope, dropped (as the loader does) |
| `inbound_logistic.csv` | `rows` | — | sourcingDT | EVERY usable lane: the primary and each backup, so P-S.1 backup sourcing can reroute |
| `inbound_logistic.csv` | `volume` | units/wk | derived | primary lane: E[D_m]; backup lanes: 0 (no planned share) |
| `inbound_logistic.csv` | `lead_time` | weeks | sourcingDT · LT_wk | clamped to 1..51 (engine limit); the 2 lanes at 52-53 wk become 51 |
| `inbound_logistic.csv` | `unit_price` | €/unit | sourcingDT · Ordering cost | per-unit cost of that lane; floored at 0.0001 |

## Policies — study → SuReSuite

Where SuReSuite has no identical policy the closest one is used, and the last column says so.

| Study (syn_effect) | SuReSuite policy | Value | Match |
|---|---|---|---|
| (s,S) replenishment: s = D·T_eff + SS, S = D·(T_eff + κ) + SS | P-P.1 inventory_control · type min_max, coverage_weeks | κ = 8 weeks | exact |
| No safety stock in the baseline | P-P.3 safety_stock_materials · fixed_days | 0 days | exact |
| Strategy 1 — ABC-XYZ safety stock SS = z·σ(D_m)·√T_s (ABC 80/95 %, XYZ CV 0.5/1.0, z 1.04–2.33) | P-P.3 per material: Supplier-stage safety_stock_days (policy_variants.abc_xyz_safety_stock) | SS_m converted to days of E[D_m], clamped 0–84 | similar — the abc_xyz variant is not reachable from /policies yet (blueprint G1), so the model's own SS_m is applied per material as days |
| Lost sales (unmet demand is lost) | P-C.1 unmet demand · backorder_allowed | false | exact |
| Primary supplier = cheapest Ordering cost, then shortest lead time | Engine primary_rank (min cost, then lead time, then id) + sourcing.primary_source overrides where they differ | see policy_overrides.csv | exact |
| Strategy 2 — backup supplier at disruption (shortest lead time, then cost) | P-S.1 backup_supplier · recovery.response = dual_source_activate | off in baseline | similar — the engine selects among the same lanes |
| Strategy 3 — resource allocation (rolling 4-week IP) | P-P.9 material_allocation · recovery.response = allocate_materials | off in baseline | similar — engine allocation LP during disruption |
| Strategy 4 — expediting | P-T.2 expedited_shipments · recovery.response = expedite_freight | off in baseline | similar |
| Strategy 5 — volume flexibility (×1.5 capacity) | P-P.5 short_term_capacity · recovery.response = capacity_flex (max_overtime_factor 1.5) | off in baseline | similar — revenue-positive overtime activation |
| Triangular demand Tri(a, b, c), ν = 0.30 | products.demand_* + outbound demand_min/max | per product | exact |
| Disruption: no deliveries from one supplier for U{5..10} weeks | scenario disruption_schedule · node:<supplier>, magnitude 100 % | 8 weeks (the mean) | similar — fixed mean duration, placed at week 12 because the engine warm-starts |

**Baseline policy defaults** (seeded): `{"fulfillment_strategy": "make_to_order", "inventory": {"type": "min_max", "coverage_weeks": 8.0, "safety_stock_method": "fixed_days", "safety_stock_days": 0, "holding_cost_pct": 0.2}, "fulfillment": {"backorder_allowed": false, "allocation": "priority"}, "sourcing": {"strategy": "single"}, "recovery": {"enabled": false, "response": []}}`

**Strategy variants**: switch a strategy on in /policies → Recovery by adding its response (`dual_source_activate`, `allocate_materials`, `expedite_freight`, `capacity_flex`). The ABC-XYZ safety stock is the `abc_xyz_safety_stock` set in `policy_overrides.csv` (one Supplier-stage `safety_stock_days` per material).

## Scenarios

- **ACCURATE_Tron baseline** — No disruption, no resilience strategy: (s,S) with kappa = 8 weeks, triangular demand, lost sales — the syn_effect baseline.
- **ACCURATE_Tron disruption — SUP-096 (multi-sourced A)** — Supplier SUP-096 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
- **ACCURATE_Tron disruption — SUP-067 (multi-sourced B)** — Supplier SUP-067 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
- **ACCURATE_Tron disruption — SUP-049 (single-sourced A)** — Supplier SUP-049 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
- **ACCURATE_Tron disruption — SUP-001 (multi-sourced C)** — Supplier SUP-001 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
- **ACCURATE_Tron disruption — SUP-069 (multi-sourced D)** — Supplier SUP-069 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
- **ACCURATE_Tron disruption — SUP-079 (single-sourced B)** — Supplier SUP-079 delivers nothing for 8 weeks (the mean of the study's U{5..10}). The study starts it at week 85-87 after a cold start; the engine warm-starts at S_m, so it is placed at week 12, inside the 52-week analysis window.
