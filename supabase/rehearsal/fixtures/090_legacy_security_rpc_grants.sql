-- Grant-adoption surface only: production metadata contains this untracked
-- signature. This fixture does not claim to reproduce its unknown legacy body.
CREATE FUNCTION public.bulk_upsert_customers(uuid,jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN; END; $$;
GRANT EXECUTE ON FUNCTION public.bulk_upsert_customers(uuid,jsonb) TO PUBLIC, anon, authenticated, service_role;
