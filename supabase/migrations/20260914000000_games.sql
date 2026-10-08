-- NFL schedule and results for the app's Games tab and the refresh planner.
--
-- One row per game from the nflverse schedule (`schedules/games.csv`).
-- `backend/refresh_schedule.py` upserts the live and previous seasons, and
-- reads kickoff times back to decide when the source probe is worth running.
-- Scores are null until nflverse posts a final. `kickoff_at` is the scheduled
-- Eastern kickoff converted to UTC.

create table if not exists public.games (
  game_id text primary key,
  season integer not null,
  season_type text not null check (season_type in ('REG', 'POST')),
  game_type text not null,
  week integer not null,
  game_date date not null,
  kickoff_at timestamptz,
  away_team text not null,
  home_team text not null,
  away_score integer,
  home_score integer,
  overtime boolean not null default false,
  stadium text,
  synced_at timestamptz not null default now()
);

create index if not exists games_season_week_idx
  on public.games(season, season_type, week);
create index if not exists games_kickoff_idx
  on public.games(kickoff_at);

alter table public.games enable row level security;

drop policy if exists "Public read games" on public.games;
create policy "Public read games"
  on public.games
  for select
  using (true);

grant select on public.games to anon, authenticated;
grant select, insert, update, delete on public.games to service_role;

notify pgrst, 'reload schema';
