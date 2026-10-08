-- A recent-form row is only useful when the app can resolve it to a snapshot.
-- The raw weekly feed includes special-team and low-participation players that
-- do not qualify for player_snapshots. Keep those source logs, but do not
-- publish anonymous leaderboard rows that cannot open a player profile.

delete from public.player_recent_form recent
where not exists (
  select 1
  from public.player_snapshots snapshot
  where snapshot.id = recent.player_id
    and snapshot.season = recent.season
);

alter table public.player_recent_form
  drop constraint if exists player_recent_form_snapshot_fkey;

alter table public.player_recent_form
  add constraint player_recent_form_snapshot_fkey
  foreign key (player_id, season)
  references public.player_snapshots (id, season)
  on delete cascade;
