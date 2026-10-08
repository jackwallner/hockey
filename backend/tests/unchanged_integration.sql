-- Run against a disposable database initialized with schema.sql and both
-- refresh migrations. Everything is rolled back at the end.
begin;
do $$
declare first_id uuid; reupload uuid; changed_id uuid; result jsonb; live_published timestamptz;
begin
  if has_function_privilege('anon','public.mark_data_refresh_unchanged(uuid,text)','execute') then
    raise exception 'anon can mark unchanged';
  end if;

  first_id := (public.record_data_refresh_probe(2026,'fp-1',p_force => true)->>'refresh_id')::uuid;
  insert into public.player_snapshots_refresh(refresh_id,id,name,team,season,season_type,player_type)
    values (first_id,1,'Fixture','SEA',2026,'REG','qb');
  insert into public.player_game_logs_refresh(refresh_id,player_id,season,season_type,game_id,game_date,week,player_type)
    values (first_id,1,2026,'REG','2026_01_SEA_NE','2026-09-10',1,'qb');
  insert into public.player_recent_form_refresh(refresh_id,player_id,season,season_type,player_type,window_weeks,as_of)
    values (first_id,1,2026,'REG','qb',3,'2026-09-10');
  perform public.update_data_refresh_build(first_id,array['REG'],1,'2026-09-10',1,1,1,1,1,'ready','pending');
  update public.data_refresh_runs set content_hash = 'hash-a' where refresh_id = first_id;
  result := public.publish_data_refresh(first_id);
  if result->>'status' not in ('published','degraded') then raise exception 'publish failed: %', result; end if;
  if (select last_success_content_hash from public.data_refresh_state) <> 'hash-a' then
    raise exception 'publish did not record the content hash';
  end if;
  live_published := (select published_at from public.data_refresh_status);

  -- A source re-upload with identical output.
  reupload := (public.record_data_refresh_probe(2026,'fp-2')->>'refresh_id')::uuid;
  result := public.mark_data_refresh_unchanged(reupload, 'hash-a');
  if result->>'status' <> 'unchanged' then raise exception 'unchanged not recorded: %', result; end if;
  if (select refresh_id from public.data_refresh_status) <> first_id then
    raise exception 'unchanged output replaced the live revision';
  end if;
  if (select published_at from public.data_refresh_status) <> live_published then
    raise exception 'unchanged output moved published_at';
  end if;
  if (select status from public.data_refresh_status) <> 'degraded' then
    raise exception 'unchanged output lost the degraded status';
  end if;
  if (public.record_data_refresh_probe(2026,'fp-2')->>'changed')::boolean then
    raise exception 'handled re-upload would rebuild again';
  end if;

  -- A different hash must not be accepted as unchanged.
  changed_id := (public.record_data_refresh_probe(2026,'fp-3')->>'refresh_id')::uuid;
  begin
    perform public.mark_data_refresh_unchanged(changed_id, 'hash-b');
    raise exception 'different output was marked unchanged';
  exception when sqlstate 'P0001' then
    null;
  end;
end $$;
rollback;
