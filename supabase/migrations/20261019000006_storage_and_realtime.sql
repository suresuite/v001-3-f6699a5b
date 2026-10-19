-- D310: platform-owned storage/realtime policies. Staging must verify signing and broker behavior.
CREATE POLICY security_private_bucket_fence ON storage.objects AS RESTRICTIVE
      FOR ALL TO PUBLIC USING (bucket_id NOT IN ('ingest','workspace','run-results'))
      WITH CHECK (bucket_id NOT IN ('ingest','workspace','run-results'));

CREATE POLICY security_project_broadcast_read ON realtime.messages
      FOR SELECT TO authenticated USING (
        CASE WHEN realtime.topic() ~ '^sim:[0-9a-fA-F-]{36}$'
          THEN public.security_project_allowed(split_part(realtime.topic(), ':', 2)::uuid, NULL)
          ELSE false END);

CREATE POLICY security_project_broadcast_fence ON realtime.messages AS RESTRICTIVE
      FOR SELECT TO PUBLIC USING (
        CASE WHEN realtime.topic() ~ '^sim:[0-9a-fA-F-]{36}$'
          THEN public.security_project_allowed(split_part(realtime.topic(), ':', 2)::uuid, NULL)
          ELSE false END);
SELECT pg_notify('pgrst', 'reload schema');
