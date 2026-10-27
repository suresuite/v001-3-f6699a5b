-- §4 D314 · THE NODE-LIST REFRESH IS ONE PASS, NOT 639.
--
-- Promoting an upload rebuilds the project's lanes (D142), and every statement on the
-- two lane tables then refreshes `node_list` for the whole project (D143). The refresh
-- was written one node at a time, and on a TRON-sized project (17 products, 560
-- materials, 61 suppliers, 1 251 lanes in each lane table) one refresh took 3.6–3.9 s on
-- an idle rehearsal database. A promotion runs it up to four times (DELETE and INSERT on
-- each lane table), so promoting the inbound file took 4.4 s locally and the outbound
-- file 12.2 s. Production answers an edge-function RPC under `authenticator`'s 8 s, and
-- the user's inbound promotion was cancelled there with "canceling statement due to
-- statement timeout" (run e92beae1-…, 2026-10-27).
--
-- Measured, the classification rules were not the cost. Three things around them were:
--
--   1. DISCOVERY RE-OFFERED EVERY NODE. `node_list_discover` inserted every node the
--      lanes name with `ON CONFLICT DO NOTHING`. Row-level BEFORE INSERT triggers fire
--      before the conflict is found, so `infer_node_list_metadata` and
--      `normalize_node_location_fields` each classified all 639 nodes per call — 0.65 s
--      for zero rows inserted. It now offers only the nodes that are missing, already
--      typed, so those triggers find nothing to infer.
--   2. THE CLASSIFIER RAN THREE TIMES PER NODE. The refresh's UPDATE used `e.echelon`
--      three times; the planner pulls the subquery up, so `classify_node_echelon` was
--      evaluated once per reference — and each evaluation is two scans of the project's
--      lanes with an OR on two columns.
--   3. EVERY ROW WAS REWRITTEN, CHANGED OR NOT, firing three row triggers per node and an
--      audit row for writes that changed nothing.
--
-- THE RULE IS STILL AUTHORED ONCE (§4 D127). The priority ladder moves out of
-- `classify_node_echelon` into `node_echelon_from_flags`, a pure function of the seven
-- facts the ladder reads. Two collectors gather those facts — `classify_node_echelon`
-- for one node (unchanged callers: `classify_node_type`, the row triggers) and
-- `node_list_attributes` for a whole project in one GROUP BY — and both decide through
-- the same function, so they cannot disagree about what a node is. BOM depth and supply
-- tier stay with their own authors (`node_bom_depth`, `node_supply_tier`), called once
-- per node. `echelonMirror.test.ts` now reads the ladder from here.
--
-- `rehearsal/920` holds the refresh to the TRON shape: the set-based answer equals the
-- per-node answer for every node, a refresh that changes nothing writes nothing, and the
-- inbound and outbound promotions each finish inside 8 s with room to spare.

-- ── the ladder, once ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.node_echelon_from_flags(
  is_outbound_target boolean,   -- a customer
  is_outbound_source boolean,   -- a product
  is_inbound_source  boolean,   -- a supplier
  is_inbound_target  boolean,   -- a purchased material
  is_bom_source      boolean,   -- consumed by something
  is_bom_target      boolean,   -- built from something
  is_plant           boolean
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
BEGIN
  is_outbound_target := COALESCE(is_outbound_target, false);
  is_outbound_source := COALESCE(is_outbound_source, false);
  is_inbound_source  := COALESCE(is_inbound_source,  false);
  is_inbound_target  := COALESCE(is_inbound_target,  false);
  is_bom_source      := COALESCE(is_bom_source,      false);
  is_bom_target      := COALESCE(is_bom_target,      false);
  is_plant           := COALESCE(is_plant,           false);

  IF is_outbound_target AND NOT (is_outbound_source OR is_bom_source OR is_bom_target
                                 OR is_inbound_source OR is_inbound_target) THEN
    RETURN 'customer';
  ELSIF is_inbound_source AND NOT (is_outbound_target OR is_outbound_source
                                   OR is_bom_source OR is_bom_target OR is_inbound_target) THEN
    RETURN 'supplier';
  ELSIF is_bom_source AND is_bom_target THEN
    RETURN 'subassembly';
  ELSIF is_outbound_source OR is_bom_target THEN
    RETURN 'product';
  ELSIF is_inbound_target OR is_bom_source THEN
    RETURN 'material';
  ELSIF is_outbound_target THEN
    RETURN 'customer';
  ELSIF is_inbound_source THEN
    RETURN 'supplier';
  ELSIF is_plant THEN
    RETURN 'plant';
  ELSE
    RETURN 'unknown';
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.node_echelon_from_flags(boolean, boolean, boolean, boolean, boolean, boolean, boolean) IS
  '§4 D314 · D127. THE echelon priority ladder, authored once. Moved verbatim out of '
  '`classify_node_echelon` so a per-node and a per-project collector decide through '
  'the same rule. `echelonMirror.test.ts` reads the branch order from this body.';

-- ── the per-node collector, unchanged except that it no longer decides ───────────
CREATE OR REPLACE FUNCTION public.classify_node_echelon(p_project_id uuid, p_node_id text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  is_outbound_target boolean := false;
  is_outbound_source boolean := false;
  is_inbound_source  boolean := false;
  is_inbound_target  boolean := false;
  is_bom_source      boolean := false;
  is_bom_target      boolean := false;
  is_plant           boolean := false;
BEGIN
  IF p_node_id IS NULL OR btrim(p_node_id) = '' THEN
    RETURN 'unknown';
  END IF;

  SELECT
    bool_or(data_source = 'outbound' AND to_location   = p_node_id),
    bool_or(data_source = 'outbound' AND from_location = p_node_id),
    bool_or(data_source = 'inbound'  AND from_location = p_node_id),
    bool_or(data_source = 'inbound'  AND to_location   = p_node_id),
    bool_or(data_source = 'bom'      AND from_location = p_node_id),
    bool_or(data_source = 'bom'      AND to_location   = p_node_id)
  INTO is_outbound_target, is_outbound_source, is_inbound_source,
       is_inbound_target, is_bom_source, is_bom_target
  FROM (
    SELECT data_source, from_location, to_location
      FROM public.supply_chain_data
     WHERE project_id = p_project_id
       AND (from_location = p_node_id OR to_location = p_node_id)
    UNION ALL
    SELECT data_source, from_location, to_location
      FROM public.supply_chain_data_multi_tier
     WHERE project_id = p_project_id
       AND (from_location = p_node_id OR to_location = p_node_id)
  ) both_lanes;

  SELECT EXISTS (
    SELECT 1 FROM public.projects p
     WHERE p.id = p_project_id AND p.plant_name = p_node_id
  ) INTO is_plant;

  RETURN public.node_echelon_from_flags(
    is_outbound_target, is_outbound_source, is_inbound_source,
    is_inbound_target, is_bom_source, is_bom_target, is_plant);
END;
$function$;

-- ── the per-project collector ────────────────────────────────────────────────────
-- Every node the project's lanes name, plus every node already in `node_list` (a node
-- whose lanes are gone keeps its row and is re-typed, as the per-node refresh did).
-- The six lane flags come from ONE scan of each lane table, unpivoted to (node, end):
-- a lane is a fact about its `from_location` and a fact about its `to_location`, which
-- is exactly what the per-node `from_location = n OR to_location = n` filter read.
CREATE OR REPLACE FUNCTION public.node_list_attributes(p_project_id uuid)
RETURNS TABLE (node_id text, in_lanes boolean, plant_name text, echelon text, bom_depth integer, supply_tier integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH lanes AS (
    SELECT s.data_source, s.from_location, s.to_location, s.plant_name
      FROM public.supply_chain_data s WHERE s.project_id = p_project_id
    UNION ALL
    SELECT t.data_source, t.from_location, t.to_location, t.plant_name
      FROM public.supply_chain_data_multi_tier t WHERE t.project_id = p_project_id
  ), ends AS (
    SELECT l.from_location AS node_id, 'from' AS side, l.data_source, l.plant_name FROM lanes l
    UNION ALL
    SELECT l.to_location, 'to', l.data_source, l.plant_name FROM lanes l
  ), flags AS (
    SELECT e.node_id,
           MIN(e.plant_name)                                        AS plant_name,
           bool_or(e.data_source = 'outbound' AND e.side = 'to')    AS outbound_target,
           bool_or(e.data_source = 'outbound' AND e.side = 'from')  AS outbound_source,
           bool_or(e.data_source = 'inbound'  AND e.side = 'from')  AS inbound_source,
           bool_or(e.data_source = 'inbound'  AND e.side = 'to')    AS inbound_target,
           bool_or(e.data_source = 'bom'      AND e.side = 'from')  AS bom_source,
           bool_or(e.data_source = 'bom'      AND e.side = 'to')    AS bom_target
      FROM ends e
     WHERE e.node_id IS NOT NULL AND btrim(e.node_id) <> ''
     GROUP BY e.node_id
  ), nodes AS (
    SELECT f.node_id FROM flags f
    UNION
    SELECT n.node_id FROM public.node_list n WHERE n.project_id = p_project_id
  )
  SELECT n.node_id,
         f.node_id IS NOT NULL,
         f.plant_name,
         CASE WHEN n.node_id IS NULL OR btrim(n.node_id) = '' THEN 'unknown'
              ELSE public.node_echelon_from_flags(
                     f.outbound_target, f.outbound_source, f.inbound_source,
                     f.inbound_target, f.bom_source, f.bom_target,
                     EXISTS (SELECT 1 FROM public.projects p
                              WHERE p.id = p_project_id AND p.plant_name = n.node_id))
         END,
         public.node_bom_depth(p_project_id, n.node_id),
         public.node_supply_tier(p_project_id, n.node_id)
    FROM nodes n
    LEFT JOIN flags f ON f.node_id = n.node_id;
$function$;

COMMENT ON FUNCTION public.node_list_attributes(uuid) IS
  '§4 D314. Every node of a project with its echelon, BOM depth and supply tier, in one '
  'pass. The echelon is decided by `node_echelon_from_flags` — the same rule '
  '`classify_node_echelon` uses for one node — so the two cannot disagree; '
  '`rehearsal/920` compares them node by node. `in_lanes` and `plant_name` are for '
  'discovery: a node no lane names is re-typed but never inserted.';

REVOKE ALL ON FUNCTION public.node_echelon_from_flags(boolean, boolean, boolean, boolean, boolean, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.node_list_attributes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.node_echelon_from_flags(boolean, boolean, boolean, boolean, boolean, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.node_list_attributes(uuid) TO service_role;

-- ── discovery: offer only what is missing, already typed ─────────────────────────
CREATE OR REPLACE FUNCTION public.node_list_discover(p_project_id uuid, p_org text, p_actor uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  inserted_count integer := 0;
BEGIN
  PERFORM public.assert_writer_may_act('node_list_discover', p_project_id, p_actor);

  -- `in_lanes` is "a lane names it": the only nodes discovery ever inserted. A node already listed is not offered, so the row-level BEFORE INSERT
  -- triggers run for new nodes only; ON CONFLICT stays for a concurrent writer.
  INSERT INTO public.node_list (project_id, plant_name, node_id, organization, created_by,
                                echelon, node_type, node_group, bom_depth, supply_tier)
  SELECT p_project_id, a.plant_name, a.node_id, p_org, p_actor,
         a.echelon,
         CASE a.echelon WHEN 'subassembly' THEN 'material' ELSE a.echelon END,
         initcap(CASE a.echelon WHEN 'subassembly' THEN 'material' ELSE a.echelon END),
         a.bom_depth, a.supply_tier
    FROM public.node_list_attributes(p_project_id) a
   WHERE a.in_lanes
     AND NOT EXISTS (SELECT 1 FROM public.node_list n
                      WHERE n.project_id = p_project_id AND n.node_id = a.node_id)
  ON CONFLICT (project_id, node_id) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

-- ── the refresh: one pass, and only rows whose values change ──────────────────────
CREATE OR REPLACE FUNCTION public.refresh_node_list_for_project(p_project_id uuid, p_actor_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_modeler uuid;
  v_email   text;
  v_actor   uuid;
  v_org     text;
BEGIN
  SELECT p.modeler_id, p.organization INTO v_modeler, v_org
  FROM public.projects p
  WHERE p.id = p_project_id;

  IF v_modeler IS NULL THEN
    RETURN;
  END IF;

  v_actor := COALESCE(p_actor_user_id, v_modeler);

  SELECT au.email INTO v_email
  FROM public.approved_users au
  WHERE au.id = v_actor
  LIMIT 1;

  PERFORM public.set_current_user_context(v_actor, COALESCE(v_email, ''));

  PERFORM public.node_list_discover(p_project_id, v_org, v_actor);

  -- MATERIALIZED: computed once, not once per reference (2. above).
  WITH a AS MATERIALIZED (
    SELECT * FROM public.node_list_attributes(p_project_id)
  ), v AS (
    SELECT a.node_id, a.echelon, a.bom_depth, a.supply_tier,
           CASE a.echelon WHEN 'subassembly' THEN 'material' ELSE a.echelon END AS node_type
      FROM a
  )
  UPDATE public.node_list nl
     SET echelon     = v.echelon,
         node_type   = v.node_type,
         node_group  = initcap(v.node_type),
         bom_depth   = v.bom_depth,
         supply_tier = v.supply_tier
    FROM v
   WHERE nl.project_id = p_project_id
     AND nl.node_id = v.node_id
     AND (nl.echelon, nl.node_type, nl.node_group, nl.bom_depth, nl.supply_tier)
         IS DISTINCT FROM (v.echelon, v.node_type, initcap(v.node_type), v.bom_depth, v.supply_tier);
END;
$function$;
