create table if not exists public.player_snapshots (
  id bigint primary key,
  name text not null,
  team text not null default 'TBD',
  position text not null default '',
  handedness text not null default '',
  image_url text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  season integer not null,
  player_type text not null default 'unknown',
  source text not null default 'baseball_savant_percentile_rankings',
  metrics jsonb not null default '[]'::jsonb,
  standard_stats jsonb not null default '[]'::jsonb,
  games jsonb not null default '[]'::jsonb
);

create index if not exists player_snapshots_team_idx on public.player_snapshots(team);
create index if not exists player_snapshots_position_idx on public.player_snapshots(position);
create index if not exists player_snapshots_updated_at_idx on public.player_snapshots(updated_at desc);
create index if not exists player_snapshots_season_idx on public.player_snapshots(season);
create index if not exists player_snapshots_player_type_idx on public.player_snapshots(player_type);

alter table public.player_snapshots enable row level security;

drop policy if exists "Public read player snapshots" on public.player_snapshots;
create policy "Public read player snapshots"
  on public.player_snapshots
  for select
  using (true);

-- Writes are performed by the service role key in GitHub Actions, which bypasses RLS.
-- No insert/update policy is required for the anon role.
