-- D309: the scoped API gateway writes its verified personal-key actor in the
-- scenario's transaction. Organization keys retain their separate service path.
CREATE OR REPLACE FUNCTION public.api_create_scenario(
 p_project_id uuid, p_scenario jsonb, _actor_user_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE columns_sql text; values_sql text; new_row public.scenarios;
BEGIN
 IF NOT public.security_is_service() THEN RAISE EXCEPTION 'internal caller required' USING ERRCODE='42501'; END IF;
 _actor_user_id := public.security_actor(_actor_user_id);
 PERFORM set_config('app.current_user_id',COALESCE(_actor_user_id::text,''),true);
 IF jsonb_typeof(p_scenario) IS DISTINCT FROM 'object' OR p_scenario ?| ARRAY['id','project_id','created_by','actor_user_id'] THEN
  RAISE EXCEPTION 'invalid scenario fields' USING ERRCODE='22023';
 END IF;
 -- The existing HTTP schema owns allowed world-model inputs. Quoted column names
 -- preserve omitted-column defaults; JSON values are parameters, never SQL text.
 SELECT string_agg(quote_ident(key),',' ORDER BY key), string_agg('s.'||quote_ident(key),',' ORDER BY key)
 INTO columns_sql,values_sql FROM jsonb_object_keys(p_scenario) key;
 IF columns_sql IS NULL THEN RAISE EXCEPTION 'scenario fields required' USING ERRCODE='22023'; END IF;
 EXECUTE format('INSERT INTO public.scenarios(project_id,%s) SELECT $1,%s FROM jsonb_populate_record(NULL::public.scenarios,$2) s RETURNING *',columns_sql,values_sql)
 INTO new_row USING p_project_id,p_scenario;
 RETURN jsonb_build_object('id',new_row.id,'name',new_row.name,'horizon_days',new_row.horizon_days,
  'replications',new_row.replications,'seed',new_row.seed,'created_at',new_row.created_at);
END;
$$;
REVOKE ALL ON FUNCTION public.api_create_scenario(uuid,jsonb,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_create_scenario(uuid,jsonb,uuid) TO service_role;
SELECT pg_notify('pgrst','reload schema');

CREATE OR REPLACE FUNCTION public.cancel_authorized_run(
 p_project_id uuid, p_run_id uuid, _actor_user_id uuid DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE changed_rows integer;
BEGIN
 _actor_user_id := public.security_actor(_actor_user_id);
 PERFORM public.security_assert_project(p_project_id,'simulation_lab');
 IF NOT EXISTS(SELECT 1 FROM public.simulation_runs WHERE id=p_run_id AND project_id=p_project_id) THEN
  RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('app.current_user_id',COALESCE(_actor_user_id::text,''),true);
 UPDATE public.simulation_runs SET status='cancelled',ended_at=now()
 WHERE id=p_run_id AND project_id=p_project_id AND status IN ('queued','running');
 GET DIAGNOSTICS changed_rows=ROW_COUNT;
 IF changed_rows>0 THEN
 PERFORM public.log_data_action(_actor_user_id,'data','run_cancelled','simulation_runs',p_run_id::text,NULL,
  jsonb_build_object('project_id',p_project_id));
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_authorized_run(uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_authorized_run(uuid,uuid,uuid) TO authenticated,service_role;
SELECT pg_notify('pgrst','reload schema');
