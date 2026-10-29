-- Tenant isolation for Neon PostgreSQL.
-- Apply after 001_initial.sql. API auth executes
-- set_config('app.current_institution', tenant_id, true) before tenant queries.
-- Run the API under a non-owner role; owner/superuser connections may bypass RLS.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','classes_and_sections','enrollments','subjects','teaching_assignments',
    'marklists','student_scores','messages_and_posts','recovery_requests','archive_vault'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t
        AND policyname='tenant_isolation'
    ) THEN
      EXECUTE format(
        'CREATE POLICY tenant_isolation ON %I USING (institution_id = current_setting(''app.current_institution'', true)) WITH CHECK (institution_id = current_setting(''app.current_institution'', true))',
        t
      );
    END IF;
  END LOOP;
END $$;

-- The institutions table is purposefully excluded so public login/community
-- signup can resolve an institution slug. Do not expose the table directly;
-- create a narrow public lookup endpoint with an allowlisted response instead.
