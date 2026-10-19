\ir helpers/verified-session.sql
-- D28's migration removes browser GUC fallback. Claims here model the gateway
-- AFTER signature verification; malformed and forged signatures run in Vitest.
DO $identity$
DECLARE signed_id uuid:=gen_random_uuid(); guc_id uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid(); got uuid;
BEGIN
  INSERT INTO public.approved_users(id,email,name,password_hash,role,is_active) VALUES
    (signed_id,'signed@example.invalid','Signed','x','user',true),
    (guc_id,'guc@example.invalid','GUC','x','super_admin',true);
  PERFORM pg_temp.browser_session(signed_id);
  PERFORM set_config('app.current_user_id',guc_id::text,true);
  IF public.get_current_user_id() IS DISTINCT FROM signed_id THEN RAISE EXCEPTION 'GUC overrode signed principal'; END IF;
  PERFORM pg_temp.browser_session(stranger);
  IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Unknown signed subject inherited GUC'; END IF;
  PERFORM pg_temp.browser_session(NULL);
  SET LOCAL ROLE authenticated;
  got:=public.get_current_user_id();
  RESET ROLE;
  IF got IS NOT NULL THEN RAISE EXCEPTION 'Browser GUC authenticated without a credential'; END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid='public.get_current_user_id()'::regprocedure)<>'s' THEN
    RAISE EXCEPTION 'Identity resolver lost STABLE';
  END IF;
END;
$identity$;
