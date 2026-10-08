-- Pre-aggregated rolling windows, one row per player per window length.
--
-- Ported from the baseball app's player_recent_form (see the baseball repo's
-- 20260725000000 migration), with the one structural change the NFL calendar
-- forces: baseball's windows are calendar days (7/15/30) because MLB plays
-- nearly every day, so a fixed number of days is a meaningful sample. The NFL
-- plays one game a week, so a day-based window would either span mostly bye
-- weeks or need to be absurdly wide. Windows here are instead the player's
-- last N games (3/5/8) — the same "how have they looked lately" question,
-- answered in units that actually track games played.
--
-- player_game_logs holds the raw per-game rows, which is the right shape for
-- one player's profile but not for ranking the league: the client would have
-- to pull and aggregate every row itself before it could sort anything. This
-- table holds one row per (player, side, window) instead, so the Stats
-- "Recent" filter, the Hot/Cold leaderboard and the leaderboard trend arrows
-- are all a single small fetch.
--
-- Modelled on Baseball Savant's rolling leaderboard, which reports THEN / NOW
-- / delta rather than a bare current-window number: `metrics` is the window
-- ending on the player's most recent game, `prior_metrics` the equal-length
-- window immediately before it, and `delta` the change between them.
--
-- Metrics stay in jsonb so the metric set can evolve without a migration —
-- the same reason player_game_logs does it.

create table if not exists public.player_recent_form (
  player_id bigint not null,
  season integer not null,
  player_type text not null, -- 'qb' | 'rb' | 'wr' | 'te' | 'def' | 'k'
  window_games integer not null, -- 3 | 5 | 8 (last N games, not calendar days)
  -- The last game_date included in the window. Lets the client tell a stale
  -- row (pipeline failed overnight) from a genuinely cold/inactive player.
  as_of date not null,
  -- The window's first and last week numbers, so the client can label a card
  -- "Weeks 15-17" instead of a raw date range. Deliberately per-row rather
  -- than a single league-wide anchor week: with byes, injuries and a
  -- postseason where only two teams still play, a shared anchor would either
  -- leave most of the board empty or misdate every other row.
  start_week integer,
  end_week integer,
  team text,
  games integer not null default 0,
  plays integer not null default 0,
  touches integer not null default 0,
  metrics jsonb not null default '{}'::jsonb,
  prior_metrics jsonb not null default '{}'::jsonb,
  delta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (player_id, season, player_type, window_games)
);

-- Leaderboard access pattern: every qualified player for one season, one
-- window, one side of the ball.
create index if not exists player_recent_form_leaderboard_idx
  on public.player_recent_form(season, window_games, player_type);

-- Profile access pattern: all three windows for one player.
create index if not exists player_recent_form_player_idx
  on public.player_recent_form(player_id, season);

create index if not exists player_recent_form_team_idx
  on public.player_recent_form(season, window_games, team);

alter table public.player_recent_form enable row level security;

drop policy if exists "Public read player recent form" on public.player_recent_form;
create policy "Public read player recent form"
  on public.player_recent_form
  for select
  using (true);

-- player_game_logs predates this migration and doesn't carry a week number,
-- which the start_week/end_week labelling above needs. Backfilled by the
-- next full ingest run (ingest_game_logs.py --full).
alter table public.player_game_logs add column if not exists week int;
