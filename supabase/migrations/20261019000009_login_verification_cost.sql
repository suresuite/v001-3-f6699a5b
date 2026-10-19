-- D312: identical public responses and bcrypt work for unknown accounts.
CREATE OR REPLACE FUNCTION public.authenticate_approved_user(user_email text, user_password text)
RETURNS TABLE(user_id uuid, user_name text, user_role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id       uuid;
  v_name     text;
  v_role     text;
  v_active   boolean;
  v_org      uuid;
  v_until    timestamptz;
  v_current  boolean;
  v_known    uuid;
  v_switched uuid;
  v_reason   text;
BEGIN
  -- Unknown addresses incur the same default bcrypt cost as ordinary password
  -- verification. Preserve the original credential query, including its behavior
  -- for legacy accounts whose email differs only in case. This salt is no secret.
  IF NOT EXISTS (SELECT 1 FROM public.approved_users WHERE lower(email)=lower(user_email)) THEN
    PERFORM extensions.crypt(user_password, '$2a$06$abcdefghijklmnopqrstuu');
  END IF;

  SELECT au.id, au.name, au.role::text, au.is_active, au.organization_id, o.access_valid_until
    INTO v_id, v_name, v_role, v_active, v_org, v_until
    FROM public.approved_users au
    LEFT JOIN public.organizations o ON o.id = au.organization_id
   WHERE lower(au.email) = lower(user_email)
     AND au.password_hash = extensions.crypt(user_password, au.password_hash)
   LIMIT 1;

  -- A super admin is not locked out by their organization's period (`20260929000004` §3).
  v_current := v_until IS NULL OR v_until > now() OR v_role = 'super_admin';

  IF v_id IS NOT NULL AND v_active THEN
    -- D216 — the DEFAULT organization, when it is not the active one and is within its
    -- period (a super admin is exempt): every sign-in lands there.
    SELECT m.org_id INTO v_switched
      FROM public.organization_members m
      JOIN public.organizations o ON o.id = m.org_id
     WHERE m.user_id = v_id
       AND m.is_default
       AND m.org_id IS DISTINCT FROM v_org
       AND (o.access_valid_until IS NULL OR o.access_valid_until > now() OR v_role = 'super_admin');
    IF v_switched IS NOT NULL THEN
      v_reason := 'default organization';
    ELSIF NOT v_current THEN
      -- D210 — the active organization's period ended and the default cannot take its
      -- place: another membership may still be current.
      SELECT m.org_id INTO v_switched
        FROM public.organization_members m
        JOIN public.organizations o ON o.id = m.org_id
       WHERE m.user_id = v_id
         AND (o.access_valid_until IS NULL OR o.access_valid_until > now())
       ORDER BY m.joined_at, m.org_id
       LIMIT 1;
      v_reason := 'active organization access period ended';
    END IF;

    IF v_switched IS NOT NULL THEN
      -- The account is the actor of its own switch (`audit-actor`), LOCAL to this call.
      PERFORM set_config('app.current_user_id', v_id::text, true);
      UPDATE public.approved_users SET organization_id = v_switched WHERE id = v_id;
      v_current := true;
    END IF;
  END IF;

  BEGIN
    IF v_id IS NOT NULL AND v_active AND v_current THEN
      IF NOT EXISTS (SELECT 1 FROM public.audit_logs
                      WHERE plane = 'access' AND action = 'auth.sign_in'
                        AND actor_user_id = v_id
                        AND created_at > now() - interval '1 minute') THEN
        INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, after)
        VALUES ('access', v_id, 'auth.sign_in', 'approved_users', v_id::text,
                jsonb_build_object('outcome', 'allowed')
                || CASE WHEN v_switched IS NULL THEN '{}'::jsonb
                        ELSE jsonb_build_object('switched_to_organization', v_switched,
                                                'reason', v_reason) END);
      END IF;
    ELSIF v_id IS NOT NULL THEN
      -- The right password on a suspended account, or one none of whose organizations
      -- is within its period. Refused, and said so on the record; the account is the TARGET.
      IF NOT EXISTS (SELECT 1 FROM public.audit_logs
                      WHERE plane = 'access' AND action = 'auth.sign_in_failed'
                        AND target_id = v_id::text
                        AND created_at > now() - interval '1 minute') THEN
        INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, after)
        VALUES ('access', NULL, 'auth.sign_in_failed', 'approved_users', v_id::text,
                jsonb_build_object('outcome', 'refused',
                  'reason', CASE WHEN NOT v_active THEN 'account suspended'
                                 ELSE 'organization access period ended' END));
      END IF;
    ELSE
      -- Recorded only for an address that is registered: an unknown address has no
      -- person to attribute it to, and recording it would let anyone write rows.
      SELECT au.id INTO v_known FROM public.approved_users au
       WHERE lower(au.email) = lower(user_email) LIMIT 1;
      IF v_known IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM public.audit_logs
                          WHERE plane = 'access' AND action = 'auth.sign_in_failed'
                            AND target_id = v_known::text
                            AND created_at > now() - interval '1 minute') THEN
        -- The ACTOR is unknown — whoever typed the wrong password is not proven to be
        -- the account holder — so it is the TARGET that names the account.
        INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, after)
        VALUES ('access', NULL, 'auth.sign_in_failed', 'approved_users', v_known::text,
                jsonb_build_object('outcome', 'refused', 'reason', 'wrong password'));
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'sign-in audit skipped: %', SQLERRM;   -- never fail a login over it
  END;

  IF v_id IS NOT NULL AND v_active AND v_current THEN
    RETURN QUERY SELECT v_id, v_name, v_role;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.authenticate_approved_user(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.authenticate_approved_user(text,text) TO service_role;
SELECT pg_notify('pgrst','reload schema');
