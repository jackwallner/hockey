# NHL Conversion Contract (shared between backend + iOS)

App: **Hockey StatScout** (working name; App Store name set by ASO research).
NHL analytics/percentiles app forked from the Football Next StatScout codebase
(itself forked from Baseball Savvy StatScout). Same architecture: event-aware
Python refresh in GitHub Actions, Supabase Postgres, SwiftUI iOS app reading
`player_snapshots` + `player_game_logs` + `player_recent_form` + `games` +
`game_details` + enrichment tables over PostgREST.

The design target is **NHL EDGE** (official percentile bars, "among forwards /
among defensemen / among goalies" cohorts) carrying **MoneyPuck**'s expected
goals model, which is what analytics-minded fans already read on the web.
Natural Stat Trick vocabulary (CF%, xGF%, HDCF%) is used where it is the
common term.

## Identity

- Repo `~/hockey`, GitHub `jackwallner/hockey` (public, so Actions is free and
  GitHub Pages works). Xcode project/scheme stay `StatScout` (as football did).
- Bundle id `com.jackwallner.hockey`. `PRODUCT_NAME` "Hockey StatScout".
  Home-screen name `StatScout`, paid tier `StatScout+`.
- Products: `com.jackwallner.hockey.pro.yearly` $9.99/yr (1-week free trial),
  `com.jackwallner.hockey.pro.monthly` $1.99/mo (1-week free trial),
  `com.jackwallner.hockey.pro` $19.99 lifetime. RevenueCat entitlement `pro`.
- Credentials: `~/.hockey_credentials` (same keys as `~/.football_credentials`).
  Supabase project lives in the football Supabase account (second free slot).
- Sim lease owner `hockey`. Feedback `jackwallner+bb@gmail.com`.
- Attribution: Settings and the About page carry "Expected goals and shot data
  from MoneyPuck.com. Schedule, box scores and bios from the NHL." MoneyPuck
  asks for attribution and nothing else; the NHL web API is unofficial.

## Data sources (all keyless, cloud-IP friendly, verified 2026-10-08)

| Source | URL | Used for |
|---|---|---|
| MoneyPuck season summary, skaters | `https://moneypuck.com/moneypuck/playerData/seasonSummary/<season>/<regular|playoffs>/skaters.csv` | season snapshots (5 rows per player: situation `all`, `5on5`, `5on4`, `4on5`, `other`) |
| MoneyPuck season summary, goalies | `.../seasonSummary/<season>/<regular|playoffs>/goalies.csv` | goalie snapshots |
| MoneyPuck season summary, teams | `.../seasonSummary/<season>/<regular|playoffs>/teams.csv` | team ratings |
| MoneyPuck shots | `https://peter-tanner.com/moneypuck/downloads/shots_<season>.zip` (zip of `shots_<season>.csv`, ~120k rows, 124 cols, ~20 MB) | per-game ixG / xGA, game details, cumulative xG series |
| NHL schedule | `https://api-web.nhle.com/v1/schedule/<YYYY-MM-DD>` (one week per call; `nextStartDate` paginates; also `regularSeasonStartDate`, `regularSeasonEndDate`, `playoffEndDate`) | `games` table |
| NHL boxscore | `https://api-web.nhle.com/v1/gamecenter/<gameId>/boxscore` → `playerByGameStats.{homeTeam,awayTeam}.{forwards,defense,goalies}` | per-game counting stats (G, A, P, +/-, PIM, hits, blocks, SOG, TOI, FO%, giveaways, takeaways; goalies saves/GA by strength, decision) |
| NHL skater/goalie summary | `https://api.nhle.com/stats/rest/en/skater/summary?limit=100&start=<n>&cayenneExp=seasonId=<YYYYYYYY> and gameTypeId=<2|3>` and `/en/goalie/summary` | standard stats that MoneyPuck lacks (+/-, PPG, PPP, SHG, GWG, W/L/OT, SO, GS) |
| NHL player landing | `https://api-web.nhle.com/v1/player/<id>/landing` | headshot, height/weight, birth date and place, shoots/catches, draft, sweater number |

`api-web.nhle.com` responses are gzip; send `Accept-Encoding` (requests does by
default). MoneyPuck files are plain static CSV, re-generated roughly daily
after the night's games. The season summary and shots file are the probe
fingerprint; the NHL endpoints are polled, not fingerprinted.

## Season

- Season label = **start year** (2026 means 2026-27). Same rule as football:
  `season = year if month >= 9 else year - 1`. `STATCAST_SEASON` env var name
  kept for workflow compatibility and overrides.
- Display label in the app: `"2026-27"` (`SeasonLabel.display(2026)`), career
  rollup season `0` displays "All Time".
- NHL API `seasonId` = `f"{season}{season+1}"`. MoneyPuck folder = `season`.
- `season_type` `REG` (gameType 2) and `POST` (gameType 3). Preseason is
  ignored everywhere.
- Oldest supported season **2008** (MoneyPuck's floor). Historical bundle:
  2008..last complete season plus season 0.
- League week (`games.week`, used only for anchoring and coverage captions):
  1-based count of 7-day blocks from the Monday on or before
  `regularSeasonStartDate`. Playoff games continue the count. The app never
  shows "Week N" to a user; it groups games by date.

## Player ids and types

- `id` = NHL player id (bigint, e.g. 8478402). MoneyPuck and the NHL API share it.
- `player_type` (lowercase): `"f"` (C, L, R, W), `"d"` (D), `"g"` (G).
  Percentiles are ranked inside the cohort: forwards against forwards,
  defensemen against defensemen, goalies against goalies. `position` keeps
  the raw code (`C`, `L`, `R`, `D`, `G`).
- `handedness` = `shootsCatches` (`L`/`R`).
- One snapshot row per player, season, season type. `REG` and `POST` ranked
  separately.

## Metric categories (jsonb `metrics[].category`, exact strings)

Metric `id` = `f"{category-slug}-{pid}-{mid}"` (`shot-quality-8478402-ixg`).
Formats: `int`, `comma`, `dec1`, `dec2`, `dec3`, `pct1` (`"54.2%"`),
`signed1` (`"+3.4"`), `sv3` (`".915"`). `inverted` = lower is better.

### `"Scoring"` (f, d) - MoneyPuck `all`, plus NHL summary
| mid | label | definition | fmt | inv |
|---|---|---|---|---|
| goals | G | I_F_goals | int | |
| assists | A | I_F_primaryAssists + I_F_secondaryAssists | int | |
| points | P | I_F_points | int | |
| points_per_60 | P/60 | points / (icetime/3600) | dec2 | |
| primary_points | Primary P | goals + primary assists | int | |
| pp_points | PP P | I_F_points at situation `5on4` | int | |
| shots_on_goal | SOG | I_F_shotsOnGoal | int | |
| shooting_pct | Sh% | goals / SOG | pct1 | |
| game_score_per_gp | Game Score | gameScore / games_played | dec2 | |

### `"Shot Quality"` (f, d) - MoneyPuck `all`
| mid | label | definition | fmt | inv |
|---|---|---|---|---|
| ixg | ixG | I_F_xGoals | dec1 | |
| gax | GAx | goals - I_F_xGoals (goals above expected) | signed1 | |
| ixg_per_60 | ixG/60 | ixG / (icetime/3600) | dec2 | |
| shot_attempts | Shot Att | I_F_shotAttempts | int | |
| shots_per_60 | Shots/60 | shot attempts / (icetime/3600) | dec1 | |
| hd_shots | HD Shots | I_F_highDangerShots | int | |
| xg_per_shot | xG/Shot | ixG / I_F_unblockedShotAttempts | dec3 | |
| rebounds_created | Rebounds | I_F_rebounds | int | |

### `"Play Driving"` (f, d) - MoneyPuck `5on5`
| mid | label | definition | fmt | inv |
|---|---|---|---|---|
| xgf_pct | xGF% | onIce_xGoalsPercentage x 100 | pct1 | |
| rel_xgf_pct | Rel xGF% | (onIce - offIce xGoalsPercentage) x 100 | signed1 | |
| cf_pct | CF% | onIce_corsiPercentage x 100 | pct1 | |
| rel_cf_pct | Rel CF% | (onIce - offIce corsiPercentage) x 100 | signed1 | |
| hdcf_pct | HDCF% | OnIce_F_highDangerShots / (F + A high danger) x 100 | pct1 | |
| gf_pct | GF% | OnIce_F_goals / (OnIce_F_goals + OnIce_A_goals) x 100 | pct1 | |
| xgf_per_60 | xGF/60 | OnIce_F_xGoals / (5on5 icetime/3600) | dec2 | |
| xga_per_60 | xGA/60 | OnIce_A_xGoals / (5on5 icetime/3600) | dec2 | yes |
| blocks | Blocks | shotsBlockedByPlayer (`all`) | int | |
| hits | Hits | I_F_hits (`all`) | int | |
| takeaways | Takeaways | I_F_takeaways (`all`) | int | |
| giveaways | Giveaways | I_F_giveaways (`all`) | int | yes |

### `"Goaltending"` (g) - MoneyPuck goalies `all`, plus NHL goalie summary
| mid | label | definition | fmt | inv |
|---|---|---|---|---|
| gsax | GSAx | xGoals - goals (goals saved above expected) | signed1 | |
| gsax_per_60 | GSAx/60 | GSAx / (icetime/3600) | dec2 | |
| sv_pct | SV% | 1 - goals / ongoal | sv3 | |
| gaa | GAA | goals / (icetime/3600) | dec2 | yes |
| hd_sv_pct | HD SV% | 1 - highDangerGoals / highDangerShots | sv3 | |
| xga_per_60 | xGA/60 | xGoals / (icetime/3600) (workload, ranked higher = busier) | dec2 | |
| rebound_pct | Rebound% | rebounds / ongoal x 100 | pct1 | yes |
| saves | Saves | ongoal - goals | int | |
| goals_against | GA | goals | int | yes |
| wins | W | NHL goalie summary `wins` | int | |
| shutouts | SO | NHL goalie summary `shutouts` | int | |

Advanced vs traditional (Swift `MetricKind`): advanced = P/60, Primary P,
Game Score, every Shot Quality metric, every Play Driving rate (xGF% .. xGA/60),
GSAx, GSAx/60, HD SV%, xGA/60, Rebound%. Traditional = G, A, P, PP P, SOG,
Sh%, Blocks, Hits, Takeaways, Giveaways, SV%, GAA, Saves, GA, W, SO.

### `standard_stats` (jsonb list of `{id: "std-<label>", label, value}`)
Skaters: `GP`, `G`, `A`, `P`, `+/-`, `PIM`, `PPG`, `PPP`, `SHG`, `GWG`, `SOG`,
`Sh%`, `TOI/GP` (`"19:42"`), `Hits`, `Blk`, `FO%` (centers with >= 50 faceoffs only).
Goalies: `GP`, `GS`, `W`, `L`, `OT`, `GAA`, `SV%`, `SO`, `SA`, `SV`.
NHL summary is the source for the fields MoneyPuck lacks; when it is
unavailable for a season the row falls back to MoneyPuck-derivable values and
omits the rest.

### Qualification
Regular season, full season: skaters `icetime >= 200 * 60` seconds at `all`
(Play Driving additionally `5on5 icetime >= 150 * 60`); goalies
`icetime >= 600 * 60` or `games_played >= 10`. Live season: thresholds scale by
`qual_scale = league games played so far / 82` with a 0.1 floor, every player
with any volume is ranked and carries `qualified`. Postseason: skaters 4 GP,
goalies 2 GP. Career (season 0): skaters 300 GP, goalies 100 GP. All of these
live in one place in `ingest.py` like football's `QUAL_*`.

## `player_game_logs` (one row per player per game)

PK `(player_id, season, season_type, game_date, player_type)`; `game_id` =
NHL game id as text. Sources: NHL boxscore (counts) joined with MoneyPuck
shots (`shooterPlayerId` / `goalieIdForShot` grouped by `game_id`) for xG.
Raw counts only, never rates. `plays` = TOI in whole minutes, `touches` =
shot attempts (skaters) or shots against (goalies).

Skater metric keys: `goals`, `assists`, `primary_assists`, `points`,
`shots_on_goal`, `shot_attempts`, `ixg`, `hd_shots`, `hits`, `blocks`,
`takeaways`, `giveaways`, `pim`, `plus_minus`, `pp_goals`, `faceoffs_won`,
`faceoffs_lost`, `toi_seconds`.
Goalie metric keys: `shots_against`, `saves`, `goals_against`, `xga`,
`hd_shots_against`, `hd_goals_against`, `toi_seconds`, `decision_win`
(1/0), `shutout` (1/0), `started` (1/0).
`primary_assists` comes from the MoneyPuck game-by-game file when the
boxscore lacks it; a null is allowed.

## `player_recent_form`

PK `(player_id, season, season_type, player_type, window_weeks)`. Windows
**2, 4, 8 weeks**, league-anchored: `anchor` = latest `game_date` with any log
row for that season and phase; current span = `(anchor - 7N days, anchor]`,
previous span = the equal-length block before it. Players without an
appearance in the current span are omitted. Rates recomputed from summed
numerators and denominators.

Skater rate keys (THEN / NOW / delta, per the existing row shape):
`points_per_60`, `goals_per_60`, `ixg_per_60`, `gax`, `shooting_pct`,
`shots_per_60`, `hd_shots_per_60`, `blocks_per_60`, `hits_per_60`; totals
`goals`, `assists`, `points`, `shots_on_goal`, `ixg`, `games`.
Goalie keys: `sv_pct`, `gaa`, `gsax`, `gsax_per_60`, `hd_sv_pct`,
`shots_against_per_60`; totals `saves`, `goals_against`, `games`, `wins`.

## `games`

`game_id` text (NHL id), `game_type` `REG` or playoff round `R1`/`R2`/`CF`/`SCF`,
`week` league week, `kickoff_at` = `startTimeUTC`, `stadium` = venue, scores
written only when `gameState` is `FINAL` or `OFF` (in-progress games stay
null; the app says "In progress" after the start time), `overtime` = last
period type `OT` or `SO`. Synced from the schedule endpoint for the live
season and the previous one.

## `game_details`

One row per final game. Exact JSON shapes (the Swift `GameDetail` decoder
reads these keys verbatim; `{value, pct}` is a rated number, a bare number
is a plain count):

- `team_stats`: `{"away": {...}, "home": {...}}` with keys `xg`, `xg_5v5`,
  `xgf_pct_5v5`, `cf_pct_5v5`, `hd_chances`, `sog`, `shot_attempts`, `goals`,
  `gax`, `pp_goals`, `pp_opportunities`, `faceoff_pct`, `hits`, `blocks`,
  `pim`. Rated: `xg`, `xg_5v5`, `xgf_pct_5v5`, `cf_pct_5v5`, `hd_chances`,
  `shot_attempts`, `gax`, `faceoff_pct` (percentile across this season's team
  games). Plain: the rest.
- `players`: list of `{role, player_id, name, team, position, toi, ...}` with
  `role` `"skater"` or `"goalie"` and `toi` in seconds. Skater keys: `goals`,
  `assists`, `points`, `sog`, `shot_attempts`, `hd_shots` (plain), `ixg`,
  `gax`, `ixg_per_60` (rated among qualifying skater games, 8+ minutes).
  Goalie keys: `shots_against`, `saves`, `goals_against` (plain), `xga`,
  `gsax`, `sv_pct` (rated among goalie games with 20+ minutes).
- `win_probability` (column name kept): the cumulative xG race as a list of
  five-number arrays `[t_seconds, away_xg, home_xg, away_goals, home_goals]`,
  one entry per shot plus a final entry at the end of the game. The Swift
  model is `XGRacePoint`.
- `big_plays`: every goal plus the five highest-xG non-goals, each
  `{period, clock, team, description, xg, result, player_id, shooter}` with
  `clock` as `"12:34"` elapsed in the period, `result` one of `GOAL`, `SAVE`,
  `MISS`, `BLOCK`, and `description` like "Snap shot, slot, rebound".

## Enrichment

- `player_profiles` (per player, live season): `jersey`, `birth_date`,
  `height_in`, `weight_lb`, `birthplace` (new column), `years_exp`,
  `rookie_season`, `draft_year`, `draft_round`, `draft_pick`, `draft_team`,
  `toi_seconds`, `toi_per_gp`, `pp_toi_seconds`, `pk_toi_seconds`,
  `toi_share` (new columns; the snap and contract and injury columns stay
  null and the app hides them when null). No free contract or injury source
  exists; the Contract Value views are removed from the hockey app.
- `team_ratings`: goals per game against an average team. Offense =
  xGF/60 and GF/60 (5v5 and all) blended, defense = xGA/60 and GA/60,
  schedule-adjusted the Simple Rating System way, shrunk and blended with
  last season as in `team_ratings.py`. `points_for/against` columns hold goals.
- `game_projections`: `home_margin` in goals, `home_win_prob` from a
  logistic on the rating gap plus home ice (~0.2 goals).

## Freshness

`data_refresh_status` keeps every column the app reads. `ngs_status` and
`pfr_status` are repurposed as `shots_status` (MoneyPuck shots file) and
`summary_status` (NHL summary); add them as new columns and leave the old
names null rather than renaming, so the Swift decoder changes once.

## Refresh cadence

MoneyPuck regenerates after the night's games (roughly 03:00-09:00 ET), the
NHL boxscore is final within minutes of the horn. Planner
(`refresh_schedule.py`): probe every 30 minutes from any game's start +2.5h
until +12h, hourly to +36h, else every 6 hours in season (Oct-Jun) and daily
off season. Schedule re-sync every 15 minutes while a game is in progress,
else daily. The event-aware probe fingerprints `skaters.csv`, `goalies.csv`,
`teams.csv` and `shots_<season>.zip` (ETag / Last-Modified / Content-Length).

## Teams (32, MoneyPuck and NHL codes agree)

ANA BOS BUF CGY CAR CHI COL CBJ DAL DET EDM FLA LAK MIN MTL NSH NJD NYI NYR
OTT PHI PIT SJS SEA STL TBL TOR UTA VAN VGK WSH WPG. Historical: ARI (to
2023-24, Coyotes; Utah is a new franchise and keeps its own record), ATL
(Thrashers, to 2010-11), PHX -> ARI. Aliases the app normalizes: `L.A`→LAK,
`N.J`→NJD, `S.J`→SJS, `T.B`→TBL, `PHX`→ARI, `WAS`→WSH, `VGK`/`VEG`→VGK,
`MON`→MTL, `CLB`→CBJ.

## Swift mapping (football → hockey)

| Football | Hockey |
|---|---|
| `MetricCategory` passing/rushing/receiving/defense | scoring/shotQuality/playDriving/goaltending |
| `PlayerPositionGroup` qb/rb/wr/te/defense | forward ("F")/defense ("D")/goalie ("G") |
| `knownTypes` qb/rb/wr/te/def | f/d/g |
| `FootballMetricRegistry` | `HockeyMetricRegistry` (same shape, catalog above) |
| primaryCategory qb→passing, rb→rushing, wr/te→receiving, def→defense | f→scoring, d→playDriving, g→goaltending |
| head-to-head compare gate (offense vs defense) | skaters vs goalies |
| `TrendWindow` 3/5/8 weeks | 2/4/8 weeks |
| `GameWeek` grouping, "Week N" | `GameDay` grouping by date, "Today / Yesterday / Tue Oct 7" |
| Win probability chart | Cumulative xG race chart |
| Contract Value views | removed |
| Snap share | TOI share |
| Season label "2026" | "2026-27" |
| `volumeCaption` "16 att" | "19:42 TOI", "41 SOG", "12 GP" |
