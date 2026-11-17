# Pre-submit deep review, 2026-11-08

Version 1.0.3 (build 17) on `origin/main` at `e3cb119`, reviewed on branch
`review/2026-11-08-hockey-deep`. Live version is 1.0.2 (last commit
`5d6531e`). The app diff since then is small: live-score polling moved into
`DashboardViewModel.pollLiveScore`, the recent-form superseded-load fix, and
the Trends season re-lock on a Pro lapse. All three are correct.

The deep pass covered every code path a user can reach: purchase, restore,
trial eligibility copy, paywall dismissal, onboarding, the Pro gates, review
prompt, settings, the player caches and data load, live scores and the views.
The app has no notifications, widgets, app intents, SwiftData/CoreData or
localization, so those checks do not apply. iPhone Duo: the iPhone-only,
portrait layout caps its content widths (tabs 900pt, paywall 680pt,
onboarding 700pt) and uses no device or screen-size checks; no defect found.
Not posed on a Duo simulator (no simulator use on this pass).

No P0. Purchase, restore, paywall, Terms/Privacy links and onboarding are
sound. Four P1/P2 bugs fixed, five P2 risks left open.

| Sev | File:line | What happens | Status |
|---|---|---|---|
| P1 | StatScout/Views/TeamView.swift:74 | Pro user, team page, Roster, Recent, Defensemen (or Forwards on Play Driving): the default sort is xGF%, which has no per-game feed, so every player is filtered out and the page reads "No players found". The loading spinner and a failed fetch were also hidden behind that empty state. | Fixed: Recent only offers and defaults to stats with a recent figure (Hits on Play Driving); loading and error show first. `TeamRosterSortTests` |
| P1 | StatScout/Views/TeamView.swift:342 | The team Advanced card was not passed `supportsRecent`, so Recent and Both were offered on past seasons and always came back "No data in the last N weeks". | Fixed: passes `supportsRecent` like the Standard card. No unit test (view parameter) |
| P1 | StatScout/Views/PlayerProfileView.swift:1251 | Player Standard tab, Recent: season totals render under the "4 wks" picker with no loading, error or empty-window line, so a failed fetch or a player with no recent games shows season numbers as if recent. | Fixed: the same status line the percentile card uses now sits under the Standard window picker. No unit test (view state) |
| P2 | StatScout/Views/TeamFormCard.swift:492 | A cancelled team form load (quick Recent/Both or season switch) set `loading = false` under the new load and could write the old season's logs over it. | Fixed: matches `TeamStandardCard`'s cancellation guard. No unit test (view task) |
| P2 | StatScout/Models/GameDetail.swift:173 | `XGRacePoint.id` is `elapsed`; two shots in the same second give duplicate ForEach ids in the xG race chart (goal markers too, GameDetailView.swift:384). Undefined SwiftUI behavior, not a crash. | Not fixed: rendering impact unconfirmed |
| P2 | StatScout/Views/CompareView.swift:164 | "Your players" lists only followed players with a row in slot A's season and phase, so moving slot A to a past season or Playoffs hides them. | Not fixed: display scope, not definite breakage |
| P2 | StatScout/Views/TeamView.swift:731 | Team page season menu writes `selectedSeason` directly rather than `selectSeason`, so a failed history load is not retried there and Teams briefly says "No teams available" while history decodes. | Not fixed: clears once history loads |
| P2 | StatScout/Views/PlayerProfileView.swift:899 | Recent/Both percentile mode ignores `isPro`, so a Pro lapse mid-session leaves recent bars on an open profile. | Not fixed: mid-session lapse only |
| P2 | StatScout/Views/PaywallView.swift:209 | When plans fail to load, the plan picker's empty state has Try Again but no Restore or Terms/Privacy. Restore stays reachable in Settings and onboarding; nothing is purchasable there. | Not fixed: no purchase path on that screen |

## Tests

`TeamRosterSortTests` added (3 cases). Unit suite run on GitHub's Macs with
`gh-sim test --scheme StatScout --skip StatScoutUITests`; result below.
