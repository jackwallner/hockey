-- Separate regular-season and postseason data throughout the NFL contract,
-- and change Trends from player-relative last-N-games windows to
-- league-anchored last-N-weeks windows.

alter table public.player_recent_form
  drop constraint if exists player_recent_form_snapshot_fkey;

alter table public.player_snapshots
  add column if not exists season_type text not null default 'REG';

alter table public.player_snapshots
  drop constraint if exists player_snapshots_pkey;

alter table public.player_snapshots
  add constraint player_snapshots_pkey
  primary key (id, season, season_type);

create index if not exists player_snapshots_season_type_idx
  on public.player_snapshots(season, season_type);

alter table public.player_game_logs
  add column if not exists season_type text not null default 'REG';

alter table public.player_game_logs
  drop constraint if exists player_game_logs_pkey;

alter table public.player_game_logs
  add constraint player_game_logs_pkey
  primary key (player_id, season, season_type, game_date, player_type);

create index if not exists player_game_logs_phase_week_idx
  on public.player_game_logs(season, season_type, week);

alter table public.player_recent_form
  add column if not exists season_type text not null default 'REG';

alter table public.player_recent_form
  add column if not exists window_weeks integer;

update public.player_recent_form
set window_weeks = window_games
where window_weeks is null;

alter table public.player_recent_form
  alter column window_weeks set not null;

alter table public.player_recent_form
  drop constraint if exists player_recent_form_pkey;

alter table public.player_recent_form
  add constraint player_recent_form_pkey
  primary key (player_id, season, season_type, player_type, window_weeks);

alter table public.player_recent_form
  drop column if exists window_games;

drop index if exists public.player_recent_form_leaderboard_idx;
create index player_recent_form_leaderboard_idx
  on public.player_recent_form(season, season_type, window_weeks, player_type);

drop index if exists public.player_recent_form_player_idx;
create index player_recent_form_player_idx
  on public.player_recent_form(player_id, season, season_type);

drop index if exists public.player_recent_form_team_idx;
create index player_recent_form_team_idx
  on public.player_recent_form(season, season_type, window_weeks, team);

delete from public.player_recent_form recent
where not exists (
  select 1
  from public.player_snapshots snapshot
  where snapshot.id = recent.player_id
    and snapshot.season = recent.season
    and snapshot.season_type = recent.season_type
);

alter table public.player_recent_form
  add constraint player_recent_form_snapshot_fkey
  foreign key (player_id, season, season_type)
  references public.player_snapshots (id, season, season_type)
  on delete cascade;
