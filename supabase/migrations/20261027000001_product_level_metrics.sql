-- §4 D313 (closes D137) · gates `input-hash`, `single-source`, `declared-capability`
-- THE PRODUCT-LEVEL VIEW'S NETWORK METRICS, COMPUTED ON THE GRAPH IT DRAWS.
--
-- `get_network_metrics_for_materials` selects from `network_nodes` — the FIRM graph —
-- and keeps a row when its `uid` equals an endpoint of a `bom` lane (D137). Firm ids
-- and material ids are two naming universes, so on a project that holds a deep-tier
-- network the Product-level page's table was EMPTY ("No material nodes with calculated
-- network metrics found"), while the analyzer answered "reused" — truthfully, about
-- a run on a different graph.
--
--   1. `product_metrics` is a kind. It reads `supply_chain_data`'s three flat lanes,
--      collapsed to the page's four echelons by the page's own function
--      (`_shared/productGraph.ts`), and keys on the PROCESS level: the lanes are
--      rebuilt by `rebuild_supply_chain_lanes`, which reads `bom_multi_level`, and the
--      product-level hash does not cover that table — the process-level hash covers
--      exactly the columns the rebuild reads. `critical_nodes` keys there for the
--      same reason.
--   2. `get_product_level_metrics` is the page's read: store ONLY, the run on the
--      current level first and the newest otherwise, each row saying whether its run
--      is current. No legacy column to fall back to — this kind never had one — so a
--      project with no run returns no rows and the page invokes the analyzer.
--
-- `get_network_metrics_for_materials` is left in place, unread by any page; its
-- rehearsal (250) still describes it. Dropping it is a follow-up, not this change.
-- ============================================================================

INSERT INTO public.analysis_kinds (kind, input_scope, fallback_scope, fallback_rule, description) VALUES
  ('product_metrics', 'process', NULL, NULL,
   'Centralities over the Product-level graph (supplier → purchased material → finished product → customer, '
   'the BOM collapsed), built from supply_chain_data''s flat lanes, which are rebuilt from the process level.')
ON CONFLICT (kind) DO UPDATE
  SET input_scope = EXCLUDED.input_scope, fallback_scope = EXCLUDED.fallback_scope,
      fallback_rule = EXCLUDED.fallback_rule, description = EXCLUDED.description;

CREATE OR REPLACE FUNCTION public.get_product_level_metrics(
  p_project_id uuid,
  p_user_id    uuid
) RETURNS TABLE(
  id                         text,
  uid                        text,
  name                       text,
  echelon                    text,
  flow                       numeric,
  degree_centrality          numeric,
  weighted_degree_centrality numeric,
  eigenvector_centrality     numeric,
  betweenness_centrality     numeric,
  closeness_centrality       numeric,
  prominence                 numeric,
  connection_count           bigint,
  metrics_source             text,
  run_id                     uuid,
  computed_from_hash         text,
  computed_at                timestamptz,
  hash_is_current            boolean
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_run     uuid;
  v_hash    text;
  v_at      timestamptz;
  v_current boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'get_product_level_metrics: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  -- LOCAL, and `has_project_access` answers for the named reader (the D169 shape).
  PERFORM set_config('app.current_user_id', p_user_id::text, true);
  IF NOT public.has_project_access(p_project_id) THEN
    RAISE EXCEPTION 'get_product_level_metrics: % cannot read project %', p_user_id, p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- §4 D238's rule: a run on the CURRENT level first; the newest otherwise, said
  -- to be stale by `hash_is_current`.
  v_run := COALESCE(public.analysis_current_run(p_project_id, 'product_metrics'),
                    public.analysis_latest_run(p_project_id, 'product_metrics'));
  IF v_run IS NULL THEN
    RETURN;
  END IF;
  SELECT r.input_hash, r.finished_at INTO v_hash, v_at FROM public.analysis_runs r WHERE r.id = v_run;
  v_current := public.analysis_run_is_current(v_run);

  RETURN QUERY
  SELECT
    ar.entity_id,
    ar.entity_id,
    COALESCE(NULLIF(btrim(CASE ar.entity_type
               WHEN 'material' THEN (SELECT m.name FROM public.materials m
                                      WHERE m.project_id = p_project_id AND m.material_id = ar.entity_id LIMIT 1)
               WHEN 'product'  THEN (SELECT p.name FROM public.products p
                                      WHERE p.project_id = p_project_id AND p.product_id = ar.entity_id LIMIT 1)
               WHEN 'supplier' THEN (SELECT s.name FROM public.suppliers s
                                      WHERE s.project_id = p_project_id AND s.supplier_id = ar.entity_id LIMIT 1)
               WHEN 'customer' THEN (SELECT c.name FROM public.customers c
                                      WHERE c.project_id = p_project_id AND c.customer_id = ar.entity_id LIMIT 1)
             END), ''), ar.entity_id),
    ar.entity_type,
    (ar.metrics ->> 'flow')::numeric,
    (ar.metrics ->> 'degree_centrality')::numeric,
    (ar.metrics ->> 'weighted_degree_centrality')::numeric,
    (ar.metrics ->> 'eigenvector_centrality')::numeric,
    (ar.metrics ->> 'betweenness_centrality')::numeric,
    (ar.metrics ->> 'closeness_centrality')::numeric,
    (ar.metrics ->> 'prominence')::numeric,
    COALESCE((ar.metrics ->> 'connections')::bigint, 0),
    'store'::text,
    v_run,
    v_hash,
    COALESCE(v_at, ar.created_at),
    v_current
  FROM public.analysis_results ar
  WHERE ar.run_id = v_run
  ORDER BY (ar.metrics ->> 'prominence')::numeric DESC NULLS LAST, ar.entity_id;
END; $fn$;

COMMENT ON FUNCTION public.get_product_level_metrics(uuid, uuid) IS
  '§4 D313. The Product-level page''s network metrics: the `product_metrics` run on the '
  'current process level, else the newest run with hash_is_current = false. Store only; '
  'no rows when no run exists. Refuses a reader without access to the project.';

REVOKE ALL ON FUNCTION public.get_product_level_metrics(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_product_level_metrics(uuid, uuid) TO anon, authenticated, service_role;
