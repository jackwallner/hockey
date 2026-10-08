-- Context tables written by backend/ingest_enrichment.py. All three are new and
-- read only by app 1.2.2 and later, so earlier builds are unaffected and the
-- job can lag or fail without touching the published snapshots.
--
-- player_profiles: bio (nflverse players), active contract (OverTheCap via
--   nflverse contracts), season snap counts, latest injury report entry.
-- team_ratings: HB-style power rating in points per game vs an average team.
-- game_projections: projected home margin and win probability, unplayed games.

create table if not exists public.player_profiles (
  player_id bigint not null,
  season integer not null,
  jersey integer,
  birth_date date,
  height_in integer,
  weight_lb integer,
  college text,
  years_exp integer,
  rookie_season integer,
  draft_year integer,
  draft_round integer,
  draft_pick integer,
  draft_team text,
  contract_apy numeric,
  contract_cap_pct numeric,
  contract_years integer,
  contract_year_signed integer,
  contract_value numeric,
  contract_guaranteed numeric,
  snap_games integer,
  team_games integer,
  off_snaps integer,
  def_snaps integer,
  st_snaps integer,
  off_snap_pct numeric,
  def_snap_pct numeric,
  injury_week integer,
  injury_status text,
  injury text,
  practice_status text,
  updated_at timestamptz not null default now(),
  primary key (player_id, season)
);

create table if not exists public.team_ratings (
  season integer not null,
  team text not null,
  rank integer not null,
  games integer not null,
  through_week integer not null,
  rating numeric not null,
  offense numeric not null,
  defense numeric not null,
  schedule numeric not null,
  prior_weight numeric not null,
  wins integer not null,
  losses integer not null,
  ties integer not null,
  points_for integer not null,
  points_against integer not null,
  updated_at timestamptz not null default now(),
  primary key (season, team)
);

create table if not exists public.game_projections (
  game_id text primary key,
  season integer not null,
  week integer not null,
  home_team text not null,
  away_team text not null,
  home_margin numeric not null,
  home_win_prob numeric not null,
  updated_at timestamptz not null default now()
);

create index if not exists game_projections_season_week_idx
  on public.game_projections(season, week);

alter table public.player_profiles enable row level security;
alter table public.team_ratings enable row level security;
alter table public.game_projections enable row level security;

drop policy if exists "Public read player profiles" on public.player_profiles;
create policy "Public read player profiles" on public.player_profiles for select using (true);
drop policy if exists "Public read team ratings" on public.team_ratings;
create policy "Public read team ratings" on public.team_ratings for select using (true);
drop policy if exists "Public read game projections" on public.game_projections;
create policy "Public read game projections" on public.game_projections for select using (true);

grant select on public.player_profiles, public.team_ratings, public.game_projections to anon, authenticated;
grant select, insert, update, delete on public.player_profiles, public.team_ratings, public.game_projections to service_role;

notify pgrst, 'reload schema';
