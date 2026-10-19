\ir helpers/verified-session.sql
-- The accepted issuer is deployment configuration, never an HTTP caller GUC.
DO $issuer$
DECLARE person uuid:=gen_random_uuid(); denied boolean;
BEGIN
 INSERT INTO public.approved_users(id,email,name,password_hash,role,is_active)
 VALUES(person,'issuer-fixture@example.invalid','Issuer fixture','x','user',true);
 PERFORM pg_temp.browser_session(person);
 PERFORM set_config('app.session_issuer','https://forged.invalid/auth/v1',true);
 IF public.get_current_user_id() IS DISTINCT FROM person THEN RAISE EXCEPTION 'Caller GUC changed configured issuer'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_set(auth.jwt(),'{iss}','"https://forged.invalid/auth/v1"')::text,true);
 IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Wrong issuer inherited identity'; END IF;

 -- An isolated staging deployment configures its URL through database maintenance.
 PERFORM pg_temp.database_maintenance();
 UPDATE public.browser_session_config SET issuer='https://isolated-stage.invalid/auth/v1';
 PERFORM pg_temp.browser_session(person);
 IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Previous deployment issuer remained accepted'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_set(auth.jwt(),'{iss}','"https://isolated-stage.invalid/auth/v1"')::text,true);
 IF public.get_current_user_id() IS DISTINCT FROM person THEN RAISE EXCEPTION 'Configured staging issuer failed'; END IF;
 SET LOCAL ROLE authenticated;
 denied:=false;
 BEGIN UPDATE public.browser_session_config SET issuer='https://forged.invalid/auth/v1';
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Browser changed session trust configuration'; END IF;
 RESET ROLE;
END;
$issuer$;
