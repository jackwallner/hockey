# Football Next 1.2

## Success criteria

Fans can open familiar NFL leaderboards, keep their team and players together,
and see which games their stats include. A validated source update reaches the
app without waiting for tomorrow's nightly job. Tests, real simulator captures,
and a TestFlight upload verify the release.

## Product scope

- Open Stats on passing yards, with the existing position and stat controls for
  rushing, receiving, defense, and advanced percentiles.
- Put free Following beside League leaders. Show each followed player's relevant
  season line and a direct link to the favorite team.
- Search the full standard leaderboard without losing a player's league rank.
- Keep coverage and refresh status visible on the screens where fans use data.
- Refresh snapshots, recent form, and open player/team screens as one revision.
- Preserve useful saved data during a failed check and explain what is shown.
- Prepare six to eight distinct App Store frames using the actual 1.2 UI.

## Audit decisions

The useful findings in `../project-docs/audits/laudit912.md` are the once-daily source race, stale
Recent Form caches, the date-only correction watermark, concurrent live writes,
and delete-before-rebuild risk. Address these together before increasing writes.

The app remains a completed-game statistics product. It cannot promise live
scores or final advanced metrics immediately after the whistle. Core stats may
publish before optional Next Gen Stats and PFR enrichment, with that distinction
visible. A week in progress is valid data; its coverage must not imply every
game in that week is included.

## Data structure and population

Keep the existing three app-facing tables, `player_snapshots`,
`player_game_logs`, and `player_recent_form`, so older installed builds continue
working. Build a candidate generation before changing live data, validate its
coverage, and publish all three plus a refresh-status record in one database
transaction. Failed candidates leave the last complete generation available.

The status contract records the season, active refresh ID, source publication
time, database publication time, latest included game date/week, and optional
enrichment availability. The app checks this revision to expire related caches.
Source publication and the phone's last check are distinct timestamps.

During September through February, GitHub Actions checks source metadata every
30 minutes. Outside the season, retain a daily safety check. Unchanged sources
exit before installing heavy dependencies or rewriting tables. Serialize writers
and promote the source fingerprint only after successful publication. Manual
force supports recovery. Reconcile the current season to include late corrections
and retain historical bundled seasons separately.

The operating target is detection within one probe interval, followed by a
validated publish. GitHub schedules and nflverse publication are best effort,
so the interface reports actual coverage instead of promising a fixed delay.
This public repository uses standard hosted runners; no paid infrastructure is
part of this change.

## Verification and rollout

1. Run backend transformation, probe, regression, and publication tests.
2. Apply the additive migration to the Football Supabase project.
3. Build and run unit/UI checks on leased headless simulators.
4. Capture and inspect the new app on iPhone and iPad. Render and independently
   review the App Store inventory, including first-three thumbnail readability.
5. Commit only release-owned files, push, and run the repository TestFlight script.
6. Dispatch the new workflow, verify populated data and the refresh-status
   endpoint, then verify an unchanged probe does no ingestion.

## Sources

- [Audit](../project-docs/audits/laudit912.md)
- [nflverse source publication notes](https://github.com/nflverse/nflverse-data/blob/main/README.Rmd)
- [GitHub Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage)
- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
