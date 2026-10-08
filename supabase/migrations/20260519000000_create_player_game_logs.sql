-- Per-player-per-game aggregated Statcast metrics. Powers the Recent Form
-- card on the player profile (last 7 / 15 / 30 day windows).
--
-- Each row is one player's contribution in one game on one side of the ball
-- (a two-way player gets separate batter and pitcher rows). Metrics live in
-- a single jsonb blob so we can evolve the metric set without migrating.

create table if not exists public.player_game_logs (
  player_id bigint not null,
  season integer not null,
  game_date date not null,
  player_type text not null, -- 'batter' | 'pitcher'
  team text,
  opponent text,
  plate_appearances integer not null default 0,
  batted_ball_events integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, game_date, player_type)
);

create index if not exists player_game_logs_player_season_idx
  on public.player_game_logs(player_id, season);
create index if not exists player_game_logs_date_idx
  on public.player_game_logs(game_date desc);
create index if not exists player_game_logs_season_date_idx
  on public.player_game_logs(season, game_date desc);

alter table public.player_game_logs enable row level security;

drop policy if exists "Public read player game logs" on public.player_game_logs;
create policy "Public read player game logs"
  on public.player_game_logs
  for select
  using (true);
