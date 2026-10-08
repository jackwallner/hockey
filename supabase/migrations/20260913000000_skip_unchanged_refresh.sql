-- Skip publishing a refresh whose output is identical to the live revision.
--
-- nflverse re-uploads release assets (Next Gen, PFR, the weekly stats file)
-- without changing a single stat. Each re-upload is a new source fingerprint,
-- so the event-aware pipeline rebuilt and republished identical rows three
-- times on 2026-09-13. That moved `published_at`, which the app shows as
-- "Updated 40m ago" when nothing had changed, and minted a new refresh_id,
-- which expires every client cache for no reason.
--
-- The builder now hashes its output. When the hash matches the live revision,
-- `mark_data_refresh_unchanged` records the new source generation as handled
-- and leaves the serving rows, refresh_id and published_at alone.

alter table public.data_refresh_runs
  add column if not exists content_hash text;

alter table public.data_refresh_state
  add column if not exists last_success_content_hash text;

alter table public.data_refresh_runs
  drop constraint if exists data_refresh_runs_status_ck;
alter table public.data_refresh_runs
  add constraint data_refresh_runs_status_ck check (
    status in ('building', 'validated', 'published', 'failed', 'degraded', 'unchanged')
  );

-- Carry the published run's hash onto the state row inside the same
-- transaction as publish_data_refresh, without rewriting that function.
create or replace function public.data_refresh_state_track_content_hash()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.last_success_refresh_id is distinct from old.last_success_refresh_id then
    select content_hash into new.last_success_content_hash
    from public.data_refresh_runs
    where refresh_id = new.last_success_refresh_id;
  end if;
  return new;
end;
$$;

drop trigger if exists data_refresh_state_track_content_hash on public.data_refresh_state;
create trigger data_refresh_state_track_content_hash
  before update on public.data_refresh_state
  for each row execute function public.data_refresh_state_track_content_hash();

create or replace function public.mark_data_refresh_unchanged(
  p_refresh_id uuid,
  p_content_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  run_row public.data_refresh_runs%rowtype;
  state_row public.data_refresh_state%rowtype;
  live_status text;
begin
  select * into run_row
  from public.data_refresh_runs
  where refresh_id = p_refresh_id
  for update;
  if not found then
    raise exception 'unknown refresh_id %', p_refresh_id using errcode = 'P0002';
  end if;
  if run_row.status not in ('building', 'validated') then
    raise exception 'refresh % is already %', p_refresh_id, run_row.status using errcode = 'P0001';
  end if;

  select * into state_row
  from public.data_refresh_state
  where singleton
  for update;

  if coalesce(p_content_hash, '') = ''
     or state_row.last_success_content_hash is distinct from p_content_hash
     or state_row.season is distinct from run_row.season then
    raise exception 'refresh % output differs from the live revision', p_refresh_id using errcode = 'P0001';
  end if;

  select status into live_status
  from public.data_refresh_runs
  where refresh_id = state_row.last_success_refresh_id;

  update public.data_refresh_runs
  set status = 'unchanged',
      content_hash = p_content_hash,
      completed_at = now(),
      error_code = null,
      error_detail = null
  where refresh_id = p_refresh_id;

  update public.data_refresh_state
  set status = case when live_status = 'degraded' then 'degraded' else 'published' end,
      current_refresh_id = null,
      last_attempt_refresh_id = p_refresh_id,
      last_success_fingerprint = run_row.source_fingerprint,
      latest_source_fingerprint = run_row.source_fingerprint,
      latest_source_published_at = run_row.source_published_at,
      last_checked_at = now(),
      last_error_code = null,
      last_error_detail = null
  where singleton;

  delete from public.player_snapshots_refresh where refresh_id = p_refresh_id;
  delete from public.player_game_logs_refresh where refresh_id = p_refresh_id;
  delete from public.player_recent_form_refresh where refresh_id = p_refresh_id;
  -- Unchanged manifests carry no payload; keep two weeks for debugging.
  delete from public.data_refresh_runs
  where status = 'unchanged'
    and completed_at < now() - interval '14 days';

  return jsonb_build_object(
    'refresh_id', state_row.last_success_refresh_id,
    'attempt_refresh_id', p_refresh_id,
    'status', 'unchanged',
    'published_at', state_row.last_success_published_at
  );
end;
$$;

revoke all on function public.mark_data_refresh_unchanged(uuid, text) from public, anon, authenticated;
grant execute on function public.mark_data_refresh_unchanged(uuid, text) to service_role;
