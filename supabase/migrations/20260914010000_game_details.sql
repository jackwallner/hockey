-- Advanced per-game box scores built from nflverse play-by-play by
-- backend/ingest_game_details.py. JSON columns keep the app contract flexible:
-- team_stats {away, home} of metric -> {value, pct} (or plain counts),
-- players [{role, player_id, name, team, ...}], win_probability
-- [[elapsed_seconds, home_wp]], big_plays [{qtr, clock, team, description,
-- epa, home_wpa}].

create table if not exists public.game_details (
  game_id text primary key,
  season integer not null,
  season_type text not null check (season_type in ('REG', 'POST')),
  week integer not null,
  away_team text not null,
  home_team text not null,
  team_stats jsonb not null default '{}'::jsonb,
  players jsonb not null default '[]'::jsonb,
  win_probability jsonb not null default '[]'::jsonb,
  big_plays jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists game_details_season_week_idx
  on public.game_details(season, season_type, week);

alter table public.game_details enable row level security;

drop policy if exists "Public read game details" on public.game_details;
create policy "Public read game details"
  on public.game_details
  for select
  using (true);

grant select on public.game_details to anon, authenticated;
grant select, insert, update, delete on public.game_details to service_role;

notify pgrst, 'reload schema';
