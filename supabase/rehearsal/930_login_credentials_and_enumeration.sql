\ir helpers/verified-session.sql
-- Login verifies passwords through the explicitly authorized service front door.
-- Legacy case-distinct email rows must not be made unreachable by normalization.
DO $login$
DECLARE a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); found_id uuid; n integer;
BEGIN
 INSERT INTO public.approved_users(id,email,name,password_hash,role,is_active) VALUES
  (a,'Login-Case@example.invalid','Case A',extensions.crypt('password-one',extensions.gen_salt('bf')),'user',true),
  (b,'login-case@example.invalid','Case B',extensions.crypt('password-two',extensions.gen_salt('bf')),'user',true);
 SET LOCAL ROLE service_role;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 SELECT user_id INTO found_id FROM public.authenticate_approved_user('LOGIN-CASE@example.invalid','password-one');
 IF found_id IS DISTINCT FROM a THEN RAISE EXCEPTION 'Existing case-distinct account A lost login'; END IF;
 SELECT user_id INTO found_id FROM public.authenticate_approved_user('login-case@example.invalid','password-two');
 IF found_id IS DISTINCT FROM b THEN RAISE EXCEPTION 'Existing case-distinct account B lost login'; END IF;
 SELECT count(*) INTO n FROM public.authenticate_approved_user('login-case@example.invalid','wrong-password');
 IF n<>0 THEN RAISE EXCEPTION 'Wrong password authenticated'; END IF;
 SELECT count(*) INTO n FROM public.authenticate_approved_user('unknown-login@example.invalid','wrong-password');
 IF n<>0 THEN RAISE EXCEPTION 'Unknown account response differed from failed credentials'; END IF;
 RESET ROLE;
 UPDATE public.approved_users SET is_active=false WHERE id=a;
 SET LOCAL ROLE service_role;
 SELECT count(*) INTO n FROM public.authenticate_approved_user('login-case@example.invalid','password-one');
 IF n<>0 THEN RAISE EXCEPTION 'Suspended account logged in'; END IF;
 RESET ROLE;
 IF has_function_privilege('anon','public.authenticate_approved_user(text,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.authenticate_approved_user(text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'Browser bypasses login throttling through credential RPC';
 END IF;
END;
$login$;
