-- Hockey refresh status: the build and publish RPCs record shots_status (the
-- MoneyPuck shots file feeding game logs) and summary_status (the NHL stats
-- summary feeding standard stats). The columns were added on
-- data_refresh_state / data_refresh_runs and the data_refresh_status view by
-- 20261008000000_hockey_schema.sql; the RPCs wrote nothing to them until now.
--
-- update_data_refresh_build gains two trailing parameters with defaults. A new
-- argument list is a new overload in Postgres, so the old 11-argument function
-- is dropped first to keep named-argument calls unambiguous.
-- publish_data_refresh publishes as 'degraded' when either status is pending or
-- degraded (like ngs_status and pfr_status before them, which stay 'unknown')
-- and copies both onto data_refresh_state. Everything else is the body of
-- 20260912000000_event_aware_refresh.sql unchanged. Idempotent.

drop function if exists public.update_data_refresh_build(
  uuid, text[], integer, date, integer, integer, integer, integer, integer, text, text
);

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
  p_pfr_status text default 'unknown',
  p_shots_status text default 'unknown',
  p_summary_status text default 'unknown'
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
      shots_status = coalesce(nullif(p_shots_status, ''), 'unknown'),
      summary_status = coalesce(nullif(p_summary_status, ''), 'unknown'),
      status = 'validated'
  where refresh_id = p_refresh_id;

  return jsonb_build_object(
    'refresh_id', p_refresh_id,
    'status', 'validated',
    'coverage_status', coverage
  );
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
        or run_row.shots_status in ('degraded', 'pending')
        or run_row.summary_status in ('degraded', 'pending')
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
        shots_status = run_row.shots_status,
        summary_status = run_row.summary_status,
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

revoke all on function public.update_data_refresh_build(uuid, text[], integer, date, integer, integer, integer, integer, integer, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.publish_data_refresh(uuid)
  from public, anon, authenticated;
grant execute on function public.update_data_refresh_build(uuid, text[], integer, date, integer, integer, integer, integer, integer, text, text, text, text)
  to service_role;
grant execute on function public.publish_data_refresh(uuid)
  to service_role;

notify pgrst, 'reload schema';
