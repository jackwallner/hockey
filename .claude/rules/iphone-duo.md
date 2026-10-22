---
paths:
  - "StatScout/Views/RootTabView.swift"
  - "StatScout/Views/DetailPaneLink.swift"
  - "StatScout/Utilities/UnfoldedSplit.swift"
  - "StatScout/Utilities/PaywallScreenshotMode.swift"
---

# Hockey StatScout: iPhone Duo (2026-10-21)

- Unfolded (regular width, at least 720 pt), `RootTabView` puts the five tabs
  and the tab bar left of the fold and the player, team or game they open in a
  pane on the right. Pane edges come from `GeometryProxy.verticalFold()`
  (iOS 27.1 `reservedRegions(.division)`), else an even split (`UnfoldedSplit`,
  unit tested). Portrait unfolded (669 pt) and every compact width keep one column.
- Player, team and game links are `DetailPaneLink`: a `NavigationLink` on a
  phone, a button that fills the right pane while split (`openInDetailPane`).
  Use it for any new player, team or game row; board rows pass
  `marksSelection: true`. Metric, stat, schedule and comparison links stay
  `NavigationLink` and push in their own pane.
- Until a row is opened, the right pane shows the Stats board leader.
- Folding only moves frames: the tabs and the detail pane stay mounted. Never
  swap layouts with an `if` on size class.
- Onboarding uses `UnfoldedPrimaryPane` so its column sits left of the fold.
- While split, the left pane's toolbar stays horizontal (`FoldSideToolbar`, in
  `RinkNavBar` and `RinkNavBarPublic`): iOS 27.1 otherwise gives that pane a
  vertical bar against the fold and narrows every board.
- White toolbar glyphs carry `toolbarGlyphDisc()`: the Duo vertical bar moves
  them off the midnight nav bar onto the light canvas.
- Ported from Gridiron StatScout (football), same chassis; keep the two in step.
- The trailing pane sets `isInDetailPane`; the player page drops its inline
  title there (the status bar shares that row and the hero names the player).
- Capture: never pass `--url` (custom-scheme `simctl openurl` raises an "Open
  in" alert, and fake schemes fail the open). gh-sim shoots each display once,
  after `--wait`, so one run captures one route per display: the tour's last
  route is the shot and earlier ones give the recording real transitions, e.g.
  `--wait 24 --record-seconds 60 --env FORCE_PRO=1 --env SCREENSHOT_MODE=1
  --args "-ScreenshotData -ResetUITestState -hasCompletedOnboarding YES
  -stats.board advanced -DuoTour -DuoRoutes trends,games,stats -DuoAt 0,8,16
  -DuoOuterRoutes games,stats -DuoOuterAt 0,10"`. Routes are in
  `RootTabView.openDuoRoute`.
