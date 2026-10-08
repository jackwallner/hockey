-- Run only against a disposable database initialized with schema.sql and the
-- event-aware migration. Every fixture change is rolled back at the end.
begin;
create function pg_temp.candidate(fingerprint text, yr integer default 2026, broken boolean default false)
returns uuid language plpgsql as $$
declare rid uuid;
begin
  rid := (public.record_data_refresh_probe(yr, fingerprint, p_force => true)->>'refresh_id')::uuid;
  insert into public.player_snapshots_refresh(refresh_id,id,name,team,season,season_type,player_type)
    values (rid,1,'Fixture','SEA',yr,'REG','qb');
  insert into public.player_game_logs_refresh(refresh_id,player_id,season,season_type,game_id,game_date,week,player_type)
    values (rid,1,yr,'REG',yr || '_01_SEA_NE',make_date(yr,9,10),1,'qb');
  insert into public.player_recent_form_refresh(refresh_id,player_id,season,season_type,player_type,window_weeks,as_of)
    values (rid,case when broken then 999 else 1 end,yr,'REG','qb',3,make_date(yr,9,10));
  perform public.update_data_refresh_build(rid,array['REG'],1,make_date(yr,9,10),1,1,1,1,1,'ready','pending');
  return rid;
end $$;

do $$
declare good uuid; bad uuid; next_id uuid; result jsonb; before_count integer;
begin
  if has_function_privilege('anon','public.publish_data_refresh(uuid)','execute') then
    raise exception 'anon can publish';
  end if;
  if has_function_privilege('authenticated','public.record_data_refresh_probe(integer,text,jsonb,timestamptz,boolean,boolean,text,text)','execute') then
    raise exception 'authenticated can write state';
  end if;
  good := pg_temp.candidate('good');
  result := public.publish_data_refresh(good);
  if result->>'status' <> 'degraded' then raise exception 'pending enrichment not exposed: %',result; end if;
  if (select refresh_id from public.player_snapshots where season=2026 limit 1) <> good then
    raise exception 'snapshot not promoted';
  end if;
  if exists(select 1 from public.player_snapshots_refresh where refresh_id=good) then
    raise exception 'published staging payload retained';
  end if;
  if (public.record_data_refresh_probe(2026,'good')->>'changed')::boolean then
    raise exception 'unchanged source started a build';
  end if;
  if (select status from public.data_refresh_status) <> 'degraded' then
    raise exception 'no-op hid pending enrichment';
  end if;
  bad := pg_temp.candidate('broken',2026,true);
  result := public.publish_data_refresh(bad);
  if result->>'status' <> 'failed' then raise exception 'bad foreign key published'; end if;
  if (select refresh_id from public.player_snapshots where season=2026 limit 1) <> good then
    raise exception 'mid-transaction failure changed live snapshots';
  end if;
  if (select refresh_id from public.player_game_logs where season=2026 limit 1) <> good then
    raise exception 'mid-transaction failure changed live logs';
  end if;
  if (select refresh_id from public.player_recent_form where season=2026 limit 1) <> good then
    raise exception 'mid-transaction failure changed live form';
  end if;
  next_id := pg_temp.candidate('next',2027);
  result := public.publish_data_refresh(next_id);
  if result->>'status' not in ('published','degraded') then raise exception 'rollover failed: %',result; end if;
  if not exists(select 1 from public.player_snapshots where season=2026 and refresh_id=good) then
    raise exception 'rollover removed prior season';
  end if;
  next_id := (public.record_data_refresh_probe(2027,'abandoned')->>'refresh_id')::uuid;
  update public.data_refresh_runs set started_at=now()-interval '3 hours' where refresh_id=next_id;
  result := public.record_data_refresh_probe(2027,'abandoned');
  if not (result->>'changed')::boolean or (result->>'refresh_id')::uuid=next_id then
    raise exception 'abandoned build blocks retries';
  end if;
  raise notice 'Publisher integration passed: access control, atomic rollback, unchanged probe, bounded staging, rollover, abandoned-run recovery';
end $$;
rollback;
