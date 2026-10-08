alter table public.player_snapshots drop constraint player_snapshots_pkey;
alter table public.player_snapshots add primary key (id, season);
