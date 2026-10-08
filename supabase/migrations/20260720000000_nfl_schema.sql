-- NFL schema (Gridiron StatScout). Idempotent: safe to run on a fresh DB or a
-- database that was cloned from the baseball app. Creates both tables if
-- absent, and renames the baseball-era game-log columns
-- (plate_appearances -> plays, batted_ball_events -> touches) when present.

-- player_snapshots: identical shape to baseball; one row per player per season.
create table if not exists public.player_snapshots (
  id bigint,
  name text not null,
  team text not null default 'TBD',
  position text not null default '',
  handedness text not null default '',
  image_url text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  season integer not null,
  player_type text not null default 'unknown',
  source text not null default 'nflverse',
  metrics jsonb not null default '[]'::jsonb,
  standard_stats jsonb not null default '[]'::jsonb,
  games jsonb not null default '[]'::jsonb,
  primary key (id, season)
);

create index if not exists player_snapshots_team_idx on public.player_snapshots(team);
create index if not exists player_snapshots_position_idx on public.player_snapshots(position);
create index if not exists player_snapshots_updated_at_idx on public.player_snapshots(updated_at desc);
create index if not exists player_snapshots_season_idx on public.player_snapshots(season);
create index if not exists player_snapshots_player_type_idx on public.player_snapshots(player_type);

alter table public.player_snapshots enable row level security;
drop policy if exists "Public read player snapshots" on public.player_snapshots;
create policy "Public read player snapshots"
  on public.player_snapshots for select using (true);

-- player_game_logs: one row per player per game per side. plays = pass attempts
-- + carries + targets; touches = completions + carries + receptions.
create table if not exists public.player_game_logs (
  player_id bigint not null,
  season integer not null,
  game_date date not null,
  player_type text not null, -- 'qb' | 'rb' | 'wr' | 'te' | 'def' | 'k'
  team text,
  opponent text,
  plays integer not null default 0,
  touches integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, game_date, player_type)
);

-- Rename baseball-era columns if this DB was cloned from the baseball app.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'player_game_logs'
      and column_name = 'plate_appearances'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'player_game_logs'
      and column_name = 'plays'
  ) then
    alter table public.player_game_logs rename column plate_appearances to plays;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'player_game_logs'
      and column_name = 'batted_ball_events'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'player_game_logs'
      and column_name = 'touches'
  ) then
    alter table public.player_game_logs rename column batted_ball_events to touches;
  end if;
end $$;

create index if not exists player_game_logs_player_season_idx
  on public.player_game_logs(player_id, season);
create index if not exists player_game_logs_date_idx
  on public.player_game_logs(game_date desc);
create index if not exists player_game_logs_season_date_idx
  on public.player_game_logs(season, game_date desc);

alter table public.player_game_logs enable row level security;
drop policy if exists "Public read player game logs" on public.player_game_logs;
create policy "Public read player game logs"
  on public.player_game_logs for select using (true);
