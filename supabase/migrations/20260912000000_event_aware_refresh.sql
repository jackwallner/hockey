-- Event-aware NFL refresh state, staging, and atomic publication.
--
-- The existing player_* tables remain the serving contract.  A refresh is
-- built in the three staging tables and one security-definer RPC replaces the
-- requested current-season phases in one database transaction.  A failed
-- build therefore leaves the previous serving rows untouched.

create extension if not exists pgcrypto;

create table if not exists public.data_refresh_runs (
  refresh_id uuid primary key,
  season integer not null,
  season_types text[] not null default array['REG']::text[],
  source_fingerprint text not null,
  source_assets jsonb not null default '[]'::jsonb,
  source_published_at timestamptz,
  status text not null default 'building',
  started_at timestamptz not null default now(),
  checked_at timestamptz not null default now(),
  completed_at timestamptz,
  published_at timestamptz,
  max_week integer,
  max_game_date date,
  expected_games integer not null default 0,
  observed_games integer not null default 0,
  coverage_status text not null default 'unknown',
  snapshot_rows integer not null default 0,
  game_log_rows integer not null default 0,
  recent_form_rows integer not null default 0,
  ngs_status text not null default 'unknown',
  pfr_status text not null default 'unknown',
  error_code text,
  error_detail text,
  constraint data_refresh_runs_status_ck check (
    status in ('building', 'validated', 'published', 'failed', 'degraded')
  ),
  constraint data_refresh_runs_coverage_ck check (
    coverage_status in ('unknown', 'partial', 'complete', 'regressed')
  )
);

create index if not exists data_refresh_runs_source_idx
  on public.data_refresh_runs(source_fingerprint, started_at desc);
create index if not exists data_refresh_runs_status_idx
  on public.data_refresh_runs(status, started_at desc);

create table if not exists public.data_refresh_state (
  singleton boolean primary key default true check (singleton),
  status text not null default 'unknown',
  season integer,
  season_type text,
  current_refresh_id uuid,
  last_attempt_refresh_id uuid,
  last_success_refresh_id uuid,
  last_success_fingerprint text,
  latest_source_fingerprint text,
  last_success_source_published_at timestamptz,
  latest_source_published_at timestamptz,
  last_success_published_at timestamptz,
  last_checked_at timestamptz,
  max_week integer,
  max_game_date date,
  expected_games integer not null default 0,
  observed_games integer not null default 0,
  coverage_status text not null default 'unknown',
  ngs_status text not null default 'unknown',
  pfr_status text not null default 'unknown',
  last_error_code text,
  last_error_detail text,
  constraint data_refresh_state_status_ck check (
    status in ('unknown', 'source_pending', 'building', 'published', 'failed', 'degraded')
  ),
  constraint data_refresh_state_coverage_ck check (
    coverage_status in ('unknown', 'partial', 'complete', 'regressed')
  )
);

insert into public.data_refresh_state(singleton)
values (true)
on conflict (singleton) do nothing;

-- Nullable columns keep old rows and existing REST/Codable clients valid while
-- making the source generation visible on rows written by the new publisher.
alter table public.player_snapshots
  add column if not exists refresh_id uuid,
  add column if not exists source_published_at timestamptz,
  add column if not exists published_at timestamptz;

alter table public.player_game_logs
  add column if not exists game_id text,
  add column if not exists refresh_id uuid,
  add column if not exists source_published_at timestamptz,
  add column if not exists published_at timestamptz;

alter table public.player_recent_form
  add column if not exists refresh_id uuid,
  add column if not exists source_published_at timestamptz,
  add column if not exists published_at timestamptz;

create index if not exists player_game_logs_game_id_idx
  on public.player_game_logs(season, season_type, game_id)
  where game_id is not null;

create table if not exists public.player_snapshots_refresh (
  refresh_id uuid not null references public.data_refresh_runs(refresh_id) on delete cascade,
  id bigint not null,
  name text not null,
  team text not null default 'TBD',
  position text not null default '',
  handedness text not null default '',
  image_url text,
  updated_at timestamptz not null default now(),
  season integer not null,
  season_type text not null default 'REG',
  player_type text not null default 'unknown',
  source text not null default 'nflverse',
  metrics jsonb not null default '[]'::jsonb,
  standard_stats jsonb not null default '[]'::jsonb,
  games jsonb not null default '[]'::jsonb,
  primary key (refresh_id, id, season, season_type)
);

create table if not exists public.player_game_logs_refresh (
  refresh_id uuid not null references public.data_refresh_runs(refresh_id) on delete cascade,
  player_id bigint not null,
  season integer not null,
  season_type text not null default 'REG',
  game_id text not null,
  game_date date not null,
  week integer,
  player_type text not null,
  team text,
  opponent text,
  plays integer not null default 0,
  touches integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (refresh_id, player_id, season, season_type, game_date, player_type)
);

create table if not exists public.player_recent_form_refresh (
  refresh_id uuid not null references public.data_refresh_runs(refresh_id) on delete cascade,
  player_id bigint not null,
  season integer not null,
  season_type text not null default 'REG',
  player_type text not null,
  window_weeks integer not null,
  as_of date not null,
  start_week integer,
  end_week integer,
  team text,
  games integer not null default 0,
  plays integer not null default 0,
  touches integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  prior_metrics jsonb not null default '{}'::jsonb,
  delta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (refresh_id, player_id, season, season_type, player_type, window_weeks)
);

create index if not exists player_snapshots_refresh_id_idx
  on public.player_snapshots_refresh(refresh_id, season, season_type);
create index if not exists player_game_logs_refresh_id_idx
  on public.player_game_logs_refresh(refresh_id, season, season_type);
create index if not exists player_recent_form_refresh_id_idx
  on public.player_recent_form_refresh(refresh_id, season, season_type);

alter table public.data_refresh_state enable row level security;
alter table public.data_refresh_runs enable row level security;
alter table public.player_snapshots_refresh enable row level security;
alter table public.player_game_logs_refresh enable row level security;
alter table public.player_recent_form_refresh enable row level security;

-- The state table contains source internals and is written only by the RPCs.
-- The curated view below is the public status contract.
revoke all on public.data_refresh_state from public, anon, authenticated;
revoke all on public.data_refresh_runs from public, anon, authenticated;
revoke all on public.player_snapshots_refresh from public, anon, authenticated;
revoke all on public.player_game_logs_refresh from public, anon, authenticated;
revoke all on public.player_recent_form_refresh from public, anon, authenticated;
grant select on public.data_refresh_state to service_role;
grant select, insert, update, delete on public.data_refresh_runs to service_role;
grant select, insert, update, delete on public.player_snapshots_refresh to service_role;
grant select, insert, update, delete on public.player_game_logs_refresh to service_role;
grant select, insert, update, delete on public.player_recent_form_refresh to service_role;

-- The app reads this one-row view through the normal Supabase REST endpoint.
-- ``refresh_id`` always identifies the live revision; latest_refresh_id is the
-- in-flight or failed attempt, which lets a client explain a pending update
-- without replacing the last good content.
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
  state.last_error_code
from public.data_refresh_state state
where state.singleton;

grant select on public.data_refresh_status to anon, authenticated, service_role;

create or replace function public.record_data_refresh_probe(
  p_season integer,
  p_source_fingerprint text,
  p_source_assets jsonb default '[]'::jsonb,
  p_source_published_at timestamptz default null,
  p_ready boolean default true,
  p_force boolean default false,
  p_error_code text default null,
  p_error_detail text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  state_row public.data_refresh_state%rowtype;
  existing_refresh uuid;
  new_refresh uuid;
begin
  select * into state_row
  from public.data_refresh_state
  where singleton
  for update;

  if not p_ready then
    update public.data_refresh_state
    set status = 'source_pending',
        season = p_season,
        latest_source_fingerprint = nullif(p_source_fingerprint, ''),
        latest_source_published_at = p_source_published_at,
        last_checked_at = now(),
        last_error_code = p_error_code,
        last_error_detail = left(p_error_detail, 1000),
        current_refresh_id = null
    where singleton;
    return jsonb_build_object(
      'changed', false,
      'ready', false,
      'status', 'source_pending'
    );
  end if;

  -- A cancelled runner can leave a building row behind.  It must not block
  -- the next probe from retrying the same source generation forever.
  update public.data_refresh_runs
  set status = 'failed',
      completed_at = now(),
      error_code = 'STALE_BUILD',
      error_detail = 'refresh worker did not complete within two hours'
  where source_fingerprint = p_source_fingerprint
    and status in ('building', 'validated')
    and started_at < now() - interval '2 hours';
  update public.data_refresh_state
  set status = 'failed',
      current_refresh_id = null,
      last_error_code = 'STALE_BUILD',
      last_error_detail = 'refresh worker did not complete within two hours'
  where singleton
    and current_refresh_id in (
      select refresh_id
      from public.data_refresh_runs
      where source_fingerprint = p_source_fingerprint
        and status = 'failed'
        and error_code = 'STALE_BUILD'
    );

  if not p_force
     and state_row.last_success_fingerprint is not null
     and state_row.last_success_fingerprint = p_source_fingerprint
     and state_row.status not in ('failed', 'building')
     and not exists (
       select 1
       from public.data_refresh_runs failed_run
       where failed_run.source_fingerprint = p_source_fingerprint
         and failed_run.status = 'failed'
         and failed_run.started_at > coalesce(
           state_row.last_success_published_at,
           '-infinity'::timestamptz
         )
     ) then
    update public.data_refresh_state
    set status = case
                   when state_row.last_success_refresh_id is null then 'unknown'
                   when state_row.status = 'degraded' then 'degraded'
                   else 'published'
                 end,
        season = coalesce(state_row.season, p_season),
        latest_source_fingerprint = p_source_fingerprint,
        latest_source_published_at = p_source_published_at,
        last_checked_at = now(),
        last_error_code = null,
        last_error_detail = null,
        current_refresh_id = null
    where singleton;
    return jsonb_build_object(
      'changed', false,
      'ready', true,
      'status', 'published',
      'refresh_id', state_row.last_success_refresh_id
    );
  end if;

  if not p_force then
    select refresh_id into existing_refresh
    from public.data_refresh_runs
    where source_fingerprint = p_source_fingerprint
      and status = 'building'
    order by started_at desc
    limit 1;
    if existing_refresh is not null then
      update public.data_refresh_state
      set status = 'building',
          season = p_season,
          current_refresh_id = existing_refresh,
          last_attempt_refresh_id = existing_refresh,
          latest_source_fingerprint = p_source_fingerprint,
          latest_source_published_at = p_source_published_at,
          last_checked_at = now()
      where singleton;
      return jsonb_build_object(
        'changed', false,
        'ready', true,
        'status', 'building',
        'refresh_id', existing_refresh
      );
    end if;
  end if;

  new_refresh := gen_random_uuid();
  insert into public.data_refresh_runs(
    refresh_id,
    season,
    source_fingerprint,
    source_assets,
    source_published_at,
    status,
    checked_at
  ) values (
    new_refresh,
    p_season,
    p_source_fingerprint,
    coalesce(p_source_assets, '[]'::jsonb),
    p_source_published_at,
    'building',
    now()
  );

  update public.data_refresh_state
  set status = 'building',
      season = p_season,
      current_refresh_id = new_refresh,
      last_attempt_refresh_id = new_refresh,
      latest_source_fingerprint = p_source_fingerprint,
      latest_source_published_at = p_source_published_at,
      last_checked_at = now(),
      last_error_code = null,
      last_error_detail = null
  where singleton;

  return jsonb_build_object(
    'changed', true,
    'ready', true,
    'status', 'building',
    'refresh_id', new_refresh
  );
end;
$$;

create or replace function public.update_data_refresh_build(
  p_refresh_id uuid,
  p_season_types text[],
  p_max_week integer,
  p_max_game_date date,
  p_expected_games integer,
  p_observed_games integer,
  p_snapshot_rows integer,
  p_game_log_rows integer,
  p_recent_form_rows integer,
  p_ngs_status text default 'unknown',
  p_pfr_status text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  run_row public.data_refresh_runs%rowtype;
  coverage text;
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

  coverage := case
    when greatest(coalesce(p_expected_games, 0), 0) > greatest(coalesce(p_observed_games, 0), 0)
      then 'partial'
    else 'complete'
  end;

  update public.data_refresh_runs
  set season_types = coalesce(nullif(p_season_types, '{}'), array['REG']::text[]),
      max_week = p_max_week,
      max_game_date = p_max_game_date,
      expected_games = greatest(coalesce(p_expected_games, 0), 0),
      observed_games = greatest(coalesce(p_observed_games, 0), 0),
      coverage_status = coverage,
      snapshot_rows = greatest(coalesce(p_snapshot_rows, 0), 0),
      game_log_rows = greatest(coalesce(p_game_log_rows, 0), 0),
      recent_form_rows = greatest(coalesce(p_recent_form_rows, 0), 0),
      ngs_status = coalesce(nullif(p_ngs_status, ''), 'unknown'),
      pfr_status = coalesce(nullif(p_pfr_status, ''), 'unknown'),
      status = 'validated'
  where refresh_id = p_refresh_id;

  return jsonb_build_object(
    'refresh_id', p_refresh_id,
    'status', 'validated',
    'coverage_status', coverage
  );
end;
$$;

create or replace function public.fail_data_refresh(
  p_refresh_id uuid,
  p_error_code text,
  p_error_detail text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.data_refresh_runs
  set status = 'failed',
      completed_at = now(),
      error_code = left(p_error_code, 120),
      error_detail = left(p_error_detail, 4000)
  where refresh_id = p_refresh_id
    and status in ('building', 'validated');

  update public.data_refresh_state
  set status = 'failed',
      current_refresh_id = null,
      last_error_code = left(p_error_code, 120),
      last_error_detail = left(p_error_detail, 1000),
      last_checked_at = now()
  where singleton
    and current_refresh_id = p_refresh_id;

  delete from public.player_snapshots_refresh where refresh_id = p_refresh_id;
  delete from public.player_game_logs_refresh where refresh_id = p_refresh_id;
  delete from public.player_recent_form_refresh where refresh_id = p_refresh_id;

  return jsonb_build_object('refresh_id', p_refresh_id, 'status', 'failed');
end;
$$;

create or replace function public.publish_data_refresh(p_refresh_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  run_row public.data_refresh_runs%rowtype;
  state_row public.data_refresh_state%rowtype;
  previous_run public.data_refresh_runs%rowtype;
  phase text;
  published_at_value timestamptz;
  final_status text;
  snapshot_count integer;
  game_log_count integer;
  recent_count integer;
  old_snapshot_count integer;
  stage_snapshot_count integer;
  old_log_count integer;
  stage_game_count integer;
  old_game_count integer;
  old_max_week integer;
  old_max_date date;
begin
  begin
    select * into run_row
    from public.data_refresh_runs
    where refresh_id = p_refresh_id
    for update;
    if not found then
      raise exception 'unknown refresh_id %', p_refresh_id using errcode = 'P0002';
    end if;
    if run_row.status <> 'validated' then
      raise exception 'refresh % is %; expected validated', p_refresh_id, run_row.status using errcode = 'P0001';
    end if;

    select * into state_row
    from public.data_refresh_state
    where singleton
    for update;
    if state_row.last_success_refresh_id is not null then
      select * into previous_run
      from public.data_refresh_runs
      where refresh_id = state_row.last_success_refresh_id;
    end if;

    select count(*) into snapshot_count
    from public.player_snapshots_refresh
    where refresh_id = p_refresh_id;
    select count(*) into game_log_count
    from public.player_game_logs_refresh
    where refresh_id = p_refresh_id;
    select count(*) into recent_count
    from public.player_recent_form_refresh
    where refresh_id = p_refresh_id;

    if snapshot_count = 0 or game_log_count = 0 or recent_count = 0 then
      raise exception 'refresh % has incomplete staged output snapshots=%, logs=%, recent=%',
        p_refresh_id, snapshot_count, game_log_count, recent_count using errcode = 'P0001';
    end if;

    if run_row.snapshot_rows <> snapshot_count
       or run_row.game_log_rows <> game_log_count
       or run_row.recent_form_rows <> recent_count then
      raise exception 'refresh % staged row counts do not match metadata', p_refresh_id using errcode = 'P0001';
    end if;

    -- Coverage comparisons are meaningful only within one season.  The
    -- singleton state survives the September rollover, so comparing a new
    -- season's Week 1 with the previous season's Week 22 would reject a valid
    -- release.
    if state_row.last_success_refresh_id is not null
       and previous_run.season = run_row.season
       and run_row.observed_games < previous_run.observed_games then
      raise exception 'refresh % regresses observed games from % to %',
        p_refresh_id, previous_run.observed_games, run_row.observed_games using errcode = 'P0001';
    end if;
    if state_row.last_success_refresh_id is not null
       and previous_run.season = run_row.season
       and previous_run.max_week is not null
       and run_row.max_week is not null
       and run_row.max_week < previous_run.max_week then
      raise exception 'refresh % regresses max week from % to %',
        p_refresh_id, previous_run.max_week, run_row.max_week using errcode = 'P0001';
    end if;
    if state_row.last_success_refresh_id is not null
       and previous_run.season = run_row.season
       and previous_run.max_game_date is not null
       and run_row.max_game_date is not null
       and run_row.max_game_date < previous_run.max_game_date then
      raise exception 'refresh % regresses max game date from % to %',
        p_refresh_id, previous_run.max_game_date, run_row.max_game_date using errcode = 'P0001';
    end if;

    foreach phase in array run_row.season_types loop
      select count(*) into old_snapshot_count
      from public.player_snapshots
      where season = run_row.season and season_type = phase;
      select count(*) into old_log_count
      from public.player_game_logs
      where season = run_row.season and season_type = phase;
      select count(*) into stage_snapshot_count
      from public.player_snapshots_refresh
      where refresh_id = p_refresh_id
        and season = run_row.season
        and season_type = phase;
      select count(*) into stage_game_count
      from (
        select distinct game_id
        from public.player_game_logs_refresh
        where refresh_id = p_refresh_id
          and season = run_row.season
          and season_type = phase
          and game_id is not null
      ) games;
      select count(*) into old_game_count
      from (
        select distinct game_id
        from public.player_game_logs
        where season = run_row.season
          and season_type = phase
          and game_id is not null
      ) games;
      if old_game_count > 0 and stage_game_count < old_game_count then
        raise exception 'refresh % drops game identities in % from % to %',
          p_refresh_id, phase, old_game_count, stage_game_count using errcode = 'P0001';
      end if;
      if exists (
        select 1
        from public.player_game_logs old_log
        where old_log.season = run_row.season
          and old_log.season_type = phase
          and old_log.game_id is not null
          and not exists (
            select 1
            from public.player_game_logs_refresh staged_log
            where staged_log.refresh_id = p_refresh_id
              and staged_log.season = old_log.season
              and staged_log.season_type = old_log.season_type
              and staged_log.game_id = old_log.game_id
          )
      ) then
        raise exception 'refresh % drops an existing game identity in %',
          p_refresh_id, phase using errcode = 'P0001';
      end if;

      select max(week), max(game_date) into old_max_week, old_max_date
      from public.player_game_logs
      where season = run_row.season and season_type = phase;
      if old_max_week is not null and (run_row.max_week is null or run_row.max_week < old_max_week) then
        raise exception 'refresh % drops week coverage in %', p_refresh_id, phase using errcode = 'P0001';
      end if;
      if old_max_date is not null and (run_row.max_game_date is null or run_row.max_game_date < old_max_date) then
        raise exception 'refresh % drops date coverage in %', p_refresh_id, phase using errcode = 'P0001';
      end if;

      -- A current live season ships every player with an opportunity.  A large
      -- sudden snapshot loss is therefore a source failure, not normal
      -- qualification churn.  Keep a generous 80 percent guard for roster
      -- corrections while rejecting empty or truncated releases.
      if old_snapshot_count > 0
         and stage_snapshot_count < greatest(1, ceil(old_snapshot_count * 0.8)) then
        raise exception 'refresh % drops snapshots in % from % to %',
          p_refresh_id, phase, old_snapshot_count, stage_snapshot_count using errcode = 'P0001';
      end if;
    end loop;

    published_at_value := clock_timestamp();

    -- Delete dependents first because player_recent_form has a foreign key to
    -- the serving snapshot set.  The whole block is transactional.
    delete from public.player_recent_form
    where season = run_row.season
      and season_type = any(run_row.season_types);
    delete from public.player_game_logs
    where season = run_row.season
      and season_type = any(run_row.season_types);
    delete from public.player_snapshots
    where season = run_row.season
      and season_type = any(run_row.season_types);

    insert into public.player_snapshots(
      id, name, team, position, handedness, image_url, updated_at, season,
      season_type, player_type, source, metrics, standard_stats, games,
      refresh_id, source_published_at, published_at
    )
    select
      id, name, team, position, handedness, image_url, updated_at, season,
      season_type, player_type, source, metrics, standard_stats, games,
      refresh_id, run_row.source_published_at, published_at_value
    from public.player_snapshots_refresh
    where refresh_id = p_refresh_id;

    insert into public.player_game_logs(
      player_id, season, season_type, game_id, game_date, week, player_type,
      team, opponent, plays, touches, metrics, updated_at, refresh_id,
      source_published_at, published_at
    )
    select
      player_id, season, season_type, game_id, game_date, week, player_type,
      team, opponent, plays, touches, metrics, updated_at, refresh_id,
      run_row.source_published_at, published_at_value
    from public.player_game_logs_refresh
    where refresh_id = p_refresh_id;

    insert into public.player_recent_form(
      player_id, season, season_type, player_type, window_weeks, as_of,
      start_week, end_week, team, games, plays, touches, metrics,
      prior_metrics, delta, updated_at, refresh_id, source_published_at,
      published_at
    )
    select
      player_id, season, season_type, player_type, window_weeks, as_of,
      start_week, end_week, team, games, plays, touches, metrics,
      prior_metrics, delta, updated_at, refresh_id, run_row.source_published_at,
      published_at_value
    from public.player_recent_form_refresh
    where refresh_id = p_refresh_id;

    final_status := case
      when run_row.ngs_status in ('degraded', 'pending')
        or run_row.pfr_status in ('degraded', 'pending')
        or run_row.coverage_status = 'partial'
        then 'degraded'
      else 'published'
    end;
    update public.data_refresh_runs
    set status = final_status,
        completed_at = published_at_value,
        published_at = published_at_value,
        error_code = null,
        error_detail = null
    where refresh_id = p_refresh_id;

    update public.data_refresh_state
    set status = final_status,
        season = run_row.season,
        season_type = array_to_string(run_row.season_types, ','),
        current_refresh_id = null,
        last_attempt_refresh_id = p_refresh_id,
        last_success_refresh_id = p_refresh_id,
        last_success_fingerprint = run_row.source_fingerprint,
        latest_source_fingerprint = run_row.source_fingerprint,
        last_success_source_published_at = run_row.source_published_at,
        latest_source_published_at = run_row.source_published_at,
        last_success_published_at = published_at_value,
        last_checked_at = coalesce(last_checked_at, now()),
        max_week = run_row.max_week,
        max_game_date = run_row.max_game_date,
        expected_games = run_row.expected_games,
        observed_games = run_row.observed_games,
        coverage_status = run_row.coverage_status,
        ngs_status = run_row.ngs_status,
        pfr_status = run_row.pfr_status,
        last_error_code = null,
        last_error_detail = null
    where singleton;

    -- Serving rows and the lightweight manifest are retained.  Payloads are
    -- disposable after a successful swap, which keeps repeated 30-minute
    -- probes from multiplying database storage.
    delete from public.player_snapshots_refresh where refresh_id = p_refresh_id;
    delete from public.player_game_logs_refresh where refresh_id = p_refresh_id;
    delete from public.player_recent_form_refresh where refresh_id = p_refresh_id;

    -- Keep ten recent run manifests for debugging and remove their payloads
    -- after fourteen days.  The current successful run is always retained.
    perform public.prune_data_refresh_history(10, interval '14 days');

    return jsonb_build_object(
      'refresh_id', p_refresh_id,
      'status', final_status,
      'coverage_status', run_row.coverage_status,
      'published_at', published_at_value,
      'snapshot_rows', snapshot_count,
      'game_log_rows', game_log_count,
      'recent_form_rows', recent_count
    );
  exception when others then
    -- PL/pgSQL rolls back the nested block's table changes before entering this
    -- handler.  Mark the attempt failed while preserving all prior live rows.
    update public.data_refresh_runs
    set status = 'failed',
        completed_at = now(),
        error_code = sqlstate,
        error_detail = left(sqlerrm, 4000)
    where refresh_id = p_refresh_id;
    delete from public.player_snapshots_refresh where refresh_id = p_refresh_id;
    delete from public.player_game_logs_refresh where refresh_id = p_refresh_id;
    delete from public.player_recent_form_refresh where refresh_id = p_refresh_id;
    update public.data_refresh_state
    set status = 'failed',
        current_refresh_id = null,
        last_attempt_refresh_id = p_refresh_id,
        last_error_code = sqlstate,
        last_error_detail = left(sqlerrm, 1000),
        last_checked_at = now()
    where singleton and current_refresh_id = p_refresh_id;
    return jsonb_build_object(
      'refresh_id', p_refresh_id,
      'status', 'failed',
      'error_code', sqlstate,
      'error_detail', left(sqlerrm, 1000)
    );
  end;
end;
$$;

create or replace function public.prune_data_refresh_history(
  p_keep_runs integer default 10,
  p_max_age interval default interval '14 days'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  doomed uuid[];
  removed integer;
begin
  -- A runner can disappear before it calls fail_data_refresh.  Discard its
  -- payload after the same two-hour lease used by the probe, while retaining
  -- the small run manifest for diagnosis.
  delete from public.player_snapshots_refresh
  where refresh_id in (
    select refresh_id from public.data_refresh_runs
    where status = 'failed'
       or (status in ('building', 'validated') and started_at < now() - interval '2 hours')
  );
  delete from public.player_game_logs_refresh
  where refresh_id in (
    select refresh_id from public.data_refresh_runs
    where status = 'failed'
       or (status in ('building', 'validated') and started_at < now() - interval '2 hours')
  );
  delete from public.player_recent_form_refresh
  where refresh_id in (
    select refresh_id from public.data_refresh_runs
    where status = 'failed'
       or (status in ('building', 'validated') and started_at < now() - interval '2 hours')
  );

  select coalesce(array_agg(refresh_id), '{}'::uuid[]) into doomed
  from (
    select refresh_id
    from public.data_refresh_runs
    where status in ('published', 'degraded', 'failed')
      and coalesce(completed_at, started_at) < now() - p_max_age
      and refresh_id not in (
        select coalesce(last_success_refresh_id, '00000000-0000-0000-0000-000000000000'::uuid)
        from public.data_refresh_state
        where singleton
      )
    order by coalesce(completed_at, started_at) desc
    offset greatest(coalesce(p_keep_runs, 10), 1)
  ) candidates;

  if cardinality(doomed) = 0 then
    return 0;
  end if;

  delete from public.player_snapshots_refresh where refresh_id = any(doomed);
  delete from public.player_game_logs_refresh where refresh_id = any(doomed);
  delete from public.player_recent_form_refresh where refresh_id = any(doomed);
  delete from public.data_refresh_runs where refresh_id = any(doomed);
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.record_data_refresh_probe(integer, text, jsonb, timestamptz, boolean, boolean, text, text)
  from public, anon, authenticated;
revoke all on function public.update_data_refresh_build(uuid, text[], integer, date, integer, integer, integer, integer, integer, text, text)
  from public, anon, authenticated;
revoke all on function public.fail_data_refresh(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.publish_data_refresh(uuid)
  from public, anon, authenticated;
revoke all on function public.prune_data_refresh_history(integer, interval)
  from public, anon, authenticated;

grant execute on function public.record_data_refresh_probe(integer, text, jsonb, timestamptz, boolean, boolean, text, text)
  to service_role;
grant execute on function public.update_data_refresh_build(uuid, text[], integer, date, integer, integer, integer, integer, integer, text, text)
  to service_role;
grant execute on function public.fail_data_refresh(uuid, text, text)
  to service_role;
grant execute on function public.publish_data_refresh(uuid)
  to service_role;
grant execute on function public.prune_data_refresh_history(integer, interval)
  to service_role;
