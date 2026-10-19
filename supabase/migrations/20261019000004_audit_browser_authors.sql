-- D309/D310: retain legacy auth.users provenance; new browser authors name approved_users.
ALTER TABLE public.experiments ADD COLUMN IF NOT EXISTS author_user_id uuid REFERENCES public.approved_users(id) ON DELETE SET NULL;
ALTER TABLE public.recovery_playbooks ADD COLUMN IF NOT EXISTS author_user_id uuid REFERENCES public.approved_users(id) ON DELETE SET NULL;
CREATE OR REPLACE FUNCTION public.security_bind_audit_actor()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.security_is_service() THEN
    PERFORM set_config('app.current_user_id', public.security_actor(NULL)::text, true);
  END IF;
  RETURN NULL;
END; $$;
CREATE OR REPLACE FUNCTION public.security_stamp_browser_author()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.security_is_service() THEN
    IF TG_OP='INSERT' THEN NEW.author_user_id := public.security_actor(NEW.author_user_id);
    ELSIF NEW.author_user_id IS DISTINCT FROM OLD.author_user_id
      AND NOT (NEW.author_user_id IS NULL AND NOT EXISTS (SELECT 1 FROM public.approved_users WHERE id=OLD.author_user_id)) THEN
      RAISE EXCEPTION 'immutable author' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER security_stamp_browser_author BEFORE INSERT OR UPDATE ON public.experiments
  FOR EACH ROW EXECUTE FUNCTION public.security_stamp_browser_author();
CREATE TRIGGER security_stamp_browser_author BEFORE INSERT OR UPDATE ON public.recovery_playbooks
  FOR EACH ROW EXECUTE FUNCTION public.security_stamp_browser_author();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.bom_multi_level FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.bom_single_level FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.customers FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.demand_forecasts FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.disruption_scenario_effects FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.disruption_scenario_profiles FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.disruption_scenario_settings FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.disruption_scenario_targets FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.disruption_scenarios FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.experiments FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.inbound_logistics FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.materials FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.multi_tier_supply_chain FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.network_edges FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.network_nodes FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.network_summary FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.node_list FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.outbound_logistics FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.policy_defaults FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.policy_overrides FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.policy_versions FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.products FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.recovery_playbooks FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.scenarios FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.suppliers FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.tier2_suppliers FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
CREATE TRIGGER security_bind_audit_actor BEFORE INSERT OR UPDATE OR DELETE ON public.tier3_suppliers FOR EACH STATEMENT EXECUTE FUNCTION public.security_bind_audit_actor();
SELECT pg_notify('pgrst', 'reload schema');
