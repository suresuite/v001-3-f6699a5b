-- Phase 7 / WP 7.1 / G15 — D310. Browser computation keeps its result shape;
-- persistence is authorized once, with immutable run bindings excluded from writes.
CREATE OR REPLACE FUNCTION public.persist_browser_result(
  p_run_id uuid, p_project_id uuid, p_replications jsonb DEFAULT '[]'::jsonb,
  p_item_series jsonb DEFAULT '[]'::jsonb, p_run_update jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.security_actor(NULL); v_run public.simulation_runs; v_update public.simulation_runs;
BEGIN
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');
  SELECT * INTO v_run FROM public.simulation_runs WHERE id = p_run_id AND project_id = p_project_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  PERFORM set_config('app.current_user_id', v_uid::text, true);
  IF jsonb_typeof(p_replications) <> 'array' OR jsonb_typeof(p_item_series) <> 'array' THEN
    RAISE EXCEPTION 'invalid result rows';
  END IF;
  INSERT INTO public.run_replications
    (run_id, project_id, rep_index, seed_used, status, kpis, time_series, warmup_at, started_at, ended_at)
  SELECT p_run_id, p_project_id, r.rep_index, r.seed_used, r.status, r.kpis, r.time_series, r.warmup_at, r.started_at, r.ended_at
    FROM jsonb_populate_recordset(NULL::public.run_replications, p_replications) r
  ON CONFLICT (run_id, rep_index) DO UPDATE SET seed_used=EXCLUDED.seed_used, status=EXCLUDED.status,
    kpis=EXCLUDED.kpis, time_series=EXCLUDED.time_series, warmup_at=EXCLUDED.warmup_at,
    started_at=EXCLUDED.started_at, ended_at=EXCLUDED.ended_at;
  INSERT INTO public.run_item_series (run_id, project_id, kind, item_id, series)
  SELECT p_run_id, p_project_id, r.kind, r.item_id, r.series
    FROM jsonb_populate_recordset(NULL::public.run_item_series, p_item_series) r
  ON CONFLICT (run_id, kind, item_id) DO UPDATE SET series=EXCLUDED.series;
  IF p_run_update IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_run_update) k WHERE k NOT IN
      ('status','ended_at','aggregate_kpis','ci_half_widths','code_version','rep_count_done','mapping_warnings','warmup_detected_at')) THEN
      RAISE EXCEPTION 'immutable run binding' USING ERRCODE = '42501';
    END IF;
    v_update := jsonb_populate_record(v_run, p_run_update);
    UPDATE public.simulation_runs SET status=v_update.status, ended_at=v_update.ended_at,
      aggregate_kpis=v_update.aggregate_kpis, ci_half_widths=v_update.ci_half_widths,
      code_version=v_update.code_version, rep_count_done=v_update.rep_count_done,
      mapping_warnings=v_update.mapping_warnings, warmup_detected_at=v_update.warmup_detected_at
    WHERE id=p_run_id AND project_id=p_project_id;
  END IF;
  PERFORM public.log_data_action(v_uid, 'data', 'browser_result_persisted', 'simulation_runs', p_run_id::text,
    NULL, jsonb_build_object('project_id', p_project_id));
END; $$;
REVOKE ALL ON FUNCTION public.persist_browser_result(uuid,uuid,jsonb,jsonb,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.persist_browser_result(uuid,uuid,jsonb,jsonb,jsonb) TO authenticated;
SELECT pg_notify('pgrst', 'reload schema');
