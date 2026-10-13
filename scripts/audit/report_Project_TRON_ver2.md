# Accuracy audit — Project TRON - ver2
Deterministic tier (tool-grounding + capability coverage). Generated 2026-07-18.

**Dataset:** 60 suppliers · 560 materials · 560 inbound arcs.

## 1. Incident reproduction — "what does supplier SUP-001 supply?"

| Fact | Value |
|---|---|
| Supplier SUP-001 name | Supplier SUP-001 (FR) |
| Materials supplier SUP-001 ACTUALLY supplies (truth) | **187** |
| get_supplier_risk #Materials for 10 (tool) | 187 |
| Tool vs truth on the count | ✅ match |

**The 5 IDs the assistant attributed to supplier SUP-001:**

| Claimed material | Exists in project? | ACTUALLY supplied by | Belongs to supplier SUP-001? |
|---|---|---|---|
| MAT-0430 | yes | SUP-054 (FR) | **NO** |
| MAT-0431 | yes | SUP-054 (FR) | **NO** |
| MAT-0432 | yes | SUP-054 (FR) | **NO** |
| MAT-0433 | yes | SUP-054 (FR) | **NO** |
| MAT-0434 | yes | SUP-054 (FR) | **NO** |

- None of the claimed IDs belongs to supplier SUP-001. All are supplied by another supplier.
- Are any of them in the first 25 rows list_project_entities would return? **no** — so they were not even a plausible unscoped tool slice; the attribution WAS ungrounded by construction (pre-H1: no supplier→material tool existed).

**Post-H1 closure (ai-agents.md §19.3 / §24.3 H1):** `get_supplier_materials("SUP-001")` now answers this from inbound_logistics:

| Check | Result |
|---|---|
| Tool enumeration vs truth (187 vs 187, ids set-equal) | ✅ match |
| Truncation note (top_n=50) | `supplier SUP-001 supplies 187 materials; showing top 50.` |
| Any incident id in the tool's supplier-SUP-001 list | ✅ none |

## 2. Capability coverage map (the root cause, generalized)

Grounded OK: 12 · PARTIAL: 0 · **GAP: 0** (of 12 probed intents)

| User question | Intent | Tool that applies | Grounded | Note |
|---|---|---|---|---|
| What does supplier SUP-001 supply? | I3 supplier→materials (enumerate) | `get_supplier_materials` | ✅ OK | Enumerates all 187 materials (= truth 187); truncation note carries the true total. THE incident closer. |
| How many materials does supplier SUP-001 supply? | supplier→material count | `get_supplier_risk` | ✅ OK | Returns #Materials = 187. |
| Who supplies material MAT-0033? | I4 material→suppliers (identify) | `get_material_suppliers` | ✅ OK | Names the actual supplier(s): SUP-001 (truth: SUP-001). |
| Is MAT-0033 single-sourced? | single-source flag | `get_material_risk` | ✅ OK | Returns Single-source Yes/No. |
| List our suppliers / materials | I1 enumerate entities | `list_project_entities` | ✅ OK | Unscoped list — correct for 'all', wrong if used to answer a scoped question. |
| Top suppliers by spend | I7 spend ranking | `get_procurement_spend` | ✅ OK | Spend ranking (ver2 has unit prices). |
| Which supplier is riskiest? | I7 risk ranking | `get_supplier_risk` | ✅ OK | Sole-source-first ranking. |
| What products use material X? | I5 material→product (BOM) | `get_bom_relations` | ✅ OK | Traverses bom_multi_level both directions (higher_level_component_id walk, useStageRows parent/leaf logic). |
| What's the lead time / price / MOQ for material X? | I2 entity detail | `get_entity_detail` | ✅ OK | Verbatim master values (cost/MOQ/holding/lead-time dist) — never imputed. |
| What policy / safety stock is set for supplier SUP-001? | I8 policy read | `get_policy_config` | ✅ OK | Exposed §5 read (personaTools.ts); default-vs-override named; pinned by cov-06 + pc-* suite. |
| Is my model validated / run-ready? | I9 validation / data-completeness read | `get_validation_status + get_data_completeness` | ✅ OK | Exposed §5 reads; pinned by cov-07 + vv-*/ds-* suites. |
| What did my last simulation run show? | I10 run results read | `get_run_results` | ✅ OK | Exposed §5 read; persisted rows only; pinned by cov-08 + vv-* suite. |

## 3. Where a tool DOES apply, is it correct? (spot checks vs truth)

- **get_supplier_risk** top-3 by sole-source exposure: 10 (187 sole / 187 mats); 965 (115 sole / 115 mats); 542 (86 sole / 86 mats)
- **get_procurement_spend** ranks by *spend*; top-3 suppliers: 10 (49639); 24439 (31039); 965 (26969)
- **get_material_risk("MAT-0033")**: suppliers=1, single-source=Yes — truth suppliers=1. ✅ match

## 4. H1 relation/detail tools vs truth (ai-agents.md §19.3)

- **get_supplier_materials("SUP-001")**: 187 materials, set-equal to truth (187) → ✅ match; incident-id leakage: none ✅
- **get_material_suppliers("MAT-0033")**: [SUP-001] vs truth [SUP-001] → ✅ match
- **get_bom_relations** (sample MAT-0001 ↑ / PRD-008 ↓): parents ✅ match; components ✅ match (156 edges vs ≥ 156 direct)
- **get_entity_detail("MAT-0033")**: cost=1.220453 moq=5712 holding=0.2 dist=deterministic — verbatim master row → ✅ match

**Finding (post-H1):** every probed I1–I10 intent is grounded (12/12 OK, 0 GAP, 0 PARTIAL) and the new tools match recomputed truth — the §19.2 target column is achieved on this dataset. The residual guarantee (a model ignoring the tools) is held by the §22.3 pre-send verifier, pinned by cov-01…cov-12.