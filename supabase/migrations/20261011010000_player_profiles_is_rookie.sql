-- The league's own Calder eligibility for the live season, from the NHL
-- stats API `isRookie` flag. Null until the enrichment job has written it.
alter table public.player_profiles add column if not exists is_rookie boolean;

notify pgrst, 'reload schema';
