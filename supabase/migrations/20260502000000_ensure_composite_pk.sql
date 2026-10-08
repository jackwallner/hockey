-- Ensure composite primary key exists for upsert operations
-- This is idempotent and safe to run multiple times

-- First, drop the single-column primary key if it exists (from old schema)
alter table if exists public.player_snapshots
  drop constraint if exists player_snapshots_pkey;

-- Add composite primary key if it doesn't exist
-- This is needed for ON CONFLICT (id, season) to work in ingest.py
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.player_snapshots'::regclass
    and conname = 'player_snapshots_pkey'
  ) then
    alter table public.player_snapshots
      add primary key (id, season);
  end if;
end $$;
