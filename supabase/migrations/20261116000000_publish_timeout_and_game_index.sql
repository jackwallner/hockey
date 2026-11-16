-- The publisher verifies that staged logs retain every live game identity.
-- Index the exact lookup key used by that anti-join.
create index if not exists player_game_logs_refresh_game_id_idx
  on public.player_game_logs_refresh(refresh_id, season, season_type, game_id);

-- The full live-season swap can exceed the PostgREST role's default 8-second
-- statement timeout once the season has several hundred games. Keep the swap
-- atomic while allowing this one publisher call to complete.
alter function public.publish_data_refresh(uuid)
  set statement_timeout = '60s';
