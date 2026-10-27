-- §4 D114 · D315 · EVERY STORED RECOVERY PLAYBOOK SPEAKS THE ENGINE'S VOCABULARY.
--
-- The engine reads a scenario's playbook as `recovery.response` (scsim
-- `project_map._map_policies`). Three things stored in this database did not reach it:
--
--   1. THE SEVEN SYSTEM PLAYBOOKS stored their strategies under `responses` (plural)
--      since `20260609000020`, and no code has ever read that key. Choosing one copied
--      `{"responses": [...]}` into the scenario's `recovery_overrides`, the card showed
--      the project default's checkboxes instead, and the run used the project default —
--      so selecting a system playbook has never changed a result (§4 D315).
--   2. `reroute` ("Network rerouting") ran P-T.2 expediting under a second name — the
--      engine's rerouting IS backup_supplier (P-S.1) — so it becomes `mode_shift`, which
--      is exactly what every run that held it executed. No number moves.
--   3. `demand_shaping` ("Material reallocation" on the card, described there as the
--      revenue-maximising allocation LP) reached no plugin. The engine's allocation LP
--      is `allocate_materials` (P-P.9), so a playbook that chose it now gets it. In a
--      PRESET it meant "reshape demand", which nothing models, so there it is dropped.
--
-- `recovery_config_canonical()` is the one rule, applied to every mutable store that
-- holds a playbook: recovery_playbooks.config, scenarios.recovery_overrides,
-- policy_defaults.recovery, policy_overrides (family recovery) and policy_presets'
-- bundle. Frozen inputs are NOT rewritten: a policy version's snapshot and a run's
-- record keep what they held, so a past run still reproduces. Only rows whose value
-- changes are updated, so no other row's updated_at moves. `rehearsal/930` holds it.

CREATE OR REPLACE FUNCTION public.recovery_config_canonical(
  cfg jsonb,
  drop_demand_shaping boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  src    jsonb;
  mapped jsonb;
BEGIN
  IF cfg IS NULL OR jsonb_typeof(cfg) <> 'object'
     OR NOT (cfg ? 'response' OR cfg ? 'responses') THEN
    RETURN cfg;
  END IF;
  -- The singular key is what the card writes; it wins over a copied plural one.
  src := CASE
           WHEN jsonb_typeof(cfg -> 'response') = 'array' THEN cfg -> 'response'
           WHEN jsonb_typeof(cfg -> 'responses') = 'array' THEN cfg -> 'responses'
           ELSE '[]'::jsonb
         END;
  SELECT COALESCE(jsonb_agg(to_jsonb(tok) ORDER BY first_seen), '[]'::jsonb)
    INTO mapped
    FROM (
      SELECT tok, min(ord) AS first_seen
        FROM (
          SELECT CASE e
                   WHEN 'reroute'          THEN 'mode_shift'
                   WHEN 'expedite_freight' THEN 'mode_shift'
                   WHEN 'demand_shaping'   THEN CASE WHEN drop_demand_shaping THEN NULL
                                                     ELSE 'allocate_materials' END
                   ELSE e
                 END AS tok,
                 ord
            FROM jsonb_array_elements_text(src) WITH ORDINALITY AS t(e, ord)
        ) x
       WHERE tok IS NOT NULL
       GROUP BY tok
    ) y;
  RETURN (cfg - 'responses') || jsonb_build_object('response', mapped);
END;
$fn$;

COMMENT ON FUNCTION public.recovery_config_canonical(jsonb, boolean) IS
  '§4 D114 · D315. A recovery playbook in the engine''s vocabulary: `responses` → '
  '`response`, `reroute`/`expedite_freight` → `mode_shift`, `demand_shaping` → '
  '`allocate_materials` (or dropped, for a preset), duplicates removed in first-seen '
  'order. Idempotent; anything without a response list is returned unchanged.';

REVOKE ALL ON FUNCTION public.recovery_config_canonical(jsonb, boolean) FROM PUBLIC, anon, authenticated;

-- AND A GAP `20261027000002` (§4 D314) LEFT, closed here: it revoked its two new
-- functions from PUBLIC only, and this database's default privileges grant EXECUTE on
-- every new function to `anon` and `authenticated` as well. `node_list_attributes` is
-- SECURITY DEFINER and returns any project's nodes for a project id, so it was callable
-- through the API by anyone holding the publishable key. Both are internal to the
-- node-list refresh (a SECURITY DEFINER caller), which needs no grant to call them.
REVOKE ALL ON FUNCTION public.node_list_attributes(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.node_echelon_from_flags(boolean, boolean, boolean, boolean, boolean, boolean, boolean)
  FROM PUBLIC, anon, authenticated;

-- ── the system playbooks: the vocabulary AND the words beside it ─────────────────
UPDATE public.recovery_playbooks
   SET name = 'Expedite Shipments',
       description = 'Accelerate in-transit material when the revenue it saves exceeds the expedite premium '
                     '(P-T.2). Fast (1–2 week TTR), higher logistics cost. Rerouting to another supplier is '
                     'the Backup Supplier playbook.',
       config = public.recovery_config_canonical(config)
 WHERE is_system AND name = 'Expedite & Reroute';

UPDATE public.recovery_playbooks
   SET name = 'Material Reallocation',
       description = 'Share scarce material between products by the revenue it earns over a rolling '
                     'planning horizon while a disruption lasts (P-P.9 allocation LP). Low cost; works when '
                     'supply is short and products compete for the same components.',
       config = public.recovery_config_canonical(config)
 WHERE is_system AND name = 'Demand-Side Flex';

UPDATE public.recovery_playbooks
   SET config = public.recovery_config_canonical(config)
 WHERE public.recovery_config_canonical(config) IS DISTINCT FROM config;

-- ── the scenarios, the project defaults and the row overrides ───────────────────
UPDATE public.scenarios
   SET recovery_overrides = public.recovery_config_canonical(recovery_overrides)
 WHERE public.recovery_config_canonical(recovery_overrides) IS DISTINCT FROM recovery_overrides;

UPDATE public.policy_defaults
   SET recovery = public.recovery_config_canonical(recovery)
 WHERE public.recovery_config_canonical(recovery) IS DISTINCT FROM recovery;

UPDATE public.policy_overrides
   SET patch = public.recovery_config_canonical(patch)
 WHERE family = 'recovery'
   AND public.recovery_config_canonical(patch) IS DISTINCT FROM patch;

-- ── the presets: "reshape demand" is not material allocation, so it is dropped ──
UPDATE public.policy_presets
   SET bundle = jsonb_set(bundle, '{recovery}',
                          public.recovery_config_canonical(bundle -> 'recovery', true))
 WHERE bundle ? 'recovery'
   AND public.recovery_config_canonical(bundle -> 'recovery', true) IS DISTINCT FROM bundle -> 'recovery';
