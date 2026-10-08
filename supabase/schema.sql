-- Gridiron StatScout (NFL) schema. Reflects the canonical remote DB.

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
  season_type text not null default 'REG',
  player_type text not null default 'unknown',
  source text not null default 'nflverse',
  metrics jsonb not null default '[]'::jsonb,
  standard_stats jsonb not null default '[]'::jsonb,
  games jsonb not null default '[]'::jsonb,
  primary key (id, season, season_type)
);

create index if not exists player_snapshots_team_idx on public.player_snapshots(team);
create index if not exists player_snapshots_position_idx on public.player_snapshots(position);
create index if not exists player_snapshots_updated_at_idx on public.player_snapshots(updated_at desc);
create index if not exists player_snapshots_season_idx on public.player_snapshots(season);
create index if not exists player_snapshots_season_type_idx on public.player_snapshots(season, season_type);
create index if not exists player_snapshots_player_type_idx on public.player_snapshots(player_type);

alter table public.player_snapshots enable row level security;

drop policy if exists "Public read player snapshots" on public.player_snapshots;
create policy "Public read player snapshots"
  on public.player_snapshots
  for select
  using (true);

-- Per-player-per-game rows. plays = pass attempts + carries + targets;
-- touches = completions + carries + receptions. Powers the Recent Form card.
create table if not exists public.player_game_logs (
  player_id bigint not null,
  season integer not null,
  season_type text not null default 'REG',
  game_date date not null,
  week integer,
  player_type text not null, -- 'qb' | 'rb' | 'wr' | 'te' | 'def' | 'k'
  team text,
  opponent text,
  plays integer not null default 0,
  touches integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, season_type, game_date, player_type)
);

create index if not exists player_game_logs_player_season_idx
  on public.player_game_logs(player_id, season);
create index if not exists player_game_logs_date_idx
  on public.player_game_logs(game_date desc);
create index if not exists player_game_logs_season_date_idx
  on public.player_game_logs(season, game_date desc);
create index if not exists player_game_logs_phase_week_idx
  on public.player_game_logs(season, season_type, week);

alter table public.player_game_logs enable row level security;

drop policy if exists "Public read player game logs" on public.player_game_logs;
create policy "Public read player game logs"
  on public.player_game_logs
  for select
  using (true);

-- League-anchored rolling windows used by Trends.
create table if not exists public.player_recent_form (
  player_id bigint not null,
  season integer not null,
  season_type text not null default 'REG',
  player_type text not null,
  window_weeks integer not null,
  as_of date not null,
  start_week integer,
  end_week integer,
  team text,
  games integer not null,
  plays integer not null,
  touches integer not null,
  metrics jsonb not null default '{}'::jsonb,
  prior_metrics jsonb not null default '{}'::jsonb,
  delta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, season_type, player_type, window_weeks),
  foreign key (player_id, season, season_type)
    references public.player_snapshots (id, season, season_type)
    on delete cascade
);

create index if not exists player_recent_form_leaderboard_idx
  on public.player_recent_form(season, season_type, window_weeks, player_type);
create index if not exists player_recent_form_player_idx
  on public.player_recent_form(player_id, season, season_type);
create index if not exists player_recent_form_team_idx
  on public.player_recent_form(season, season_type, window_weeks, team);

alter table public.player_recent_form enable row level security;

drop policy if exists "Public read player recent form" on public.player_recent_form;
create policy "Public read player recent form"
  on public.player_recent_form
  for select
  using (true);

-- Writes are performed by the service role key in GitHub Actions, which bypasses RLS.
-- No insert/update policy is required for the anon role.
