alter table public.player_snapshots
  add column if not exists standard_stats jsonb not null default '[]'::jsonb;
