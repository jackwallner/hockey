-- How a final ended past regulation: 'OT', 'SO', or '2OT' and up for a
-- playoff game. Null in regulation and before the final. `overtime` stays
-- for the readers that only need the standings point.
alter table public.games add column if not exists final_period text;

notify pgrst, 'reload schema';
