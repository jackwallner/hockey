-- Keep data_refresh_status read-only for client roles.
--
-- Earlier migrations grant only SELECT, but Supabase's default privileges on
-- the public schema also gave anon and authenticated INSERT, UPDATE and DELETE.
-- The view is a simple single-table view owned by postgres, so PostgREST
-- writes through it would land on data_refresh_state and skip its RLS. Clients
-- and the refresh scripts only read it; writers use the security definer RPCs.
--
-- A later `drop view` + `create view` resets grants to the defaults, so any
-- migration that recreates the view must repeat this revoke. Idempotent.

revoke insert, update, delete, truncate, references, trigger
  on public.data_refresh_status from anon, authenticated;

grant select on public.data_refresh_status to anon, authenticated, service_role;

notify pgrst, 'reload schema';
