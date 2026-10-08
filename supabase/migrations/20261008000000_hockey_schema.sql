-- Hockey StatScout (NHL) schema changes on top of the source-agnostic base.
-- Idempotent: safe to re-run.
--
-- 1. player_profiles gains the NHL bio and ice-time columns. The NFL snap,
--    contract and injury columns stay (null for hockey, the app hides them).
-- 2. data_refresh_state / data_refresh_runs gain shots_status (MoneyPuck shots
--    file) and summary_status (NHL stats summary). ngs_status and pfr_status
--    keep their names and are simply left at 'unknown'.
-- 3. data_refresh_status is re-created with the two new columns after every
--    existing column.
-- 4. Player type vocabulary is f / d / g (forward, defenseman, goalie), and the
--    source default is moneypuck. Documented as column comments because no
--    CHECK constraint ever enforced the NFL list.

alter table public.player_profiles
  add column if not exists birthplace text,
  add column if not exists toi_seconds integer,
  add column if not exists toi_per_gp numeric,
  add column if not exists pp_toi_seconds integer,
  add column if not exists pk_toi_seconds integer,
  add column if not exists toi_share numeric;

alter table public.data_refresh_state
  add column if not exists shots_status text not null default 'unknown',
  add column if not exists summary_status text not null default 'unknown';

alter table public.data_refresh_runs
  add column if not exists shots_status text not null default 'unknown',
  add column if not exists summary_status text not null default 'unknown';

drop view if exists public.data_refresh_status;
create view public.data_refresh_status as
select
  state.status,
  state.last_success_refresh_id as refresh_id,
  coalesce(state.current_refresh_id, state.last_attempt_refresh_id) as latest_refresh_id,
  state.last_success_refresh_id,
  state.last_success_fingerprint as source_fingerprint,
  state.latest_source_fingerprint,
  state.last_success_source_published_at as source_published_at,
  state.latest_source_published_at,
  state.last_success_published_at as published_at,
  state.last_checked_at,
  state.season,
  state.season_type,
  state.max_week,
  state.max_game_date,
  state.expected_games,
  state.observed_games,
  state.coverage_status,
  state.ngs_status,
  state.pfr_status,
  state.last_error_code,
  state.shots_status,
  state.summary_status
from public.data_refresh_state state
where state.singleton;

grant select on public.data_refresh_status to anon, authenticated, service_role;

alter table public.player_snapshots alter column source set default 'moneypuck';
alter table public.player_snapshots_refresh alter column source set default 'moneypuck';

comment on column public.player_snapshots.player_type is
  'f (C/L/R/W) | d (D) | g (G)';
comment on column public.player_snapshots_refresh.player_type is
  'f (C/L/R/W) | d (D) | g (G)';
comment on column public.player_game_logs.player_type is
  'f (C/L/R/W) | d (D) | g (G)';
comment on column public.player_game_logs_refresh.player_type is
  'f (C/L/R/W) | d (D) | g (G)';
comment on column public.player_recent_form.player_type is
  'f (C/L/R/W) | d (D) | g (G)';
comment on column public.player_recent_form_refresh.player_type is
  'f (C/L/R/W) | d (D) | g (G)';

notify pgrst, 'reload schema';
