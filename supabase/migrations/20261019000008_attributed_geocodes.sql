-- D309: service-backed geocoding keeps the verified caller in the SAME write
-- transaction as the audit triggers; a pooled preliminary context RPC is inert.
CREATE OR REPLACE FUNCTION public.apply_geocode(
  p_project_id uuid, p_node_id uuid, p_location_text text,
  p_latitude numeric, p_longitude numeric, _actor_user_id uuid,
  p_plant boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');
  IF _actor_user_id IS NULL THEN RAISE EXCEPTION 'actor required' USING ERRCODE='22004'; END IF;
  PERFORM set_config('app.current_user_id',_actor_user_id::text,true);
  IF p_plant THEN
    UPDATE public.projects SET plant_location_text=p_location_text,
      plant_latitude=p_latitude, plant_longitude=p_longitude WHERE id=p_project_id;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.node_list WHERE id=p_node_id AND project_id=p_project_id) THEN
      RAISE EXCEPTION 'node does not belong to project' USING ERRCODE='42501';
    END IF;
    UPDATE public.node_list SET location_text=p_location_text,
      latitude=p_latitude, longitude=p_longitude WHERE id=p_node_id AND project_id=p_project_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.apply_geocode(uuid,uuid,text,numeric,numeric,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_geocode(uuid,uuid,text,numeric,numeric,uuid,boolean) TO authenticated, service_role;
SELECT pg_notify('pgrst','reload schema');
