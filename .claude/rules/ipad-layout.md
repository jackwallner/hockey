---
paths:
  - "StatScout/Views/RootTabView.swift"
  - "StatScout/Views/CompareView.swift"
  - "StatScout/Views/PaywallView.swift"
  - "StatScout/Views/TrialPitchSheet.swift"
  - "StatScout/Views/PaywallScreenshotHarness.swift"
  - "StatScout/StatScoutApp.swift"
  - "StatScoutUITests/StatScoutIPadUITests.swift"
  - "project.yml"
---

# Hockey Edge: iPad layout

iPad is native: `TARGETED_DEVICE_FAMILY "1,2"`, all four orientations in
Info.plist (`UISupportedInterfaceOrientations~ipad`), Split View and Slide Over
allowed. There is no separate iPad design; the phone layout is held to a
readable column.

- `RinkLayout.columnWidth` (900pt, in CompareView.swift) caps tab content.
  `RinkNavBarPublic` applies the cap inside each navigation stack, so the navy
  nav bar spans the whole window and only the boards stay centred. Do not cap
  the stack from outside: the bar then stops at the column edge and the status
  bar text runs over it.
- Onboarding caps at 700pt, the paywall scroll content at 680pt.
- The trial pitch is a form sheet and the paywall a page sheet on iPad (`rinkFormSheet()`, `rinkPageSheet()`,
  `presentationSizing(.form)`, iOS 18+, a no-op on iPhone). Detents alone
  produced a near full-width card with a huge empty middle.
- The DEBUG `-PaywallSnapshot` harness presents the paywall and pitch as real
  sheets on iPad so captures match what ships.

## Verifying

`StatScoutIPadUITests` tours onboarding, paywall, pitch, every tab, profiles,
game detail, compare and Settings in portrait and landscape on the DEBUG
fixture. Run it on the 13-inch iPad through gh-sim:

```
gh-sim test --scheme StatScoutUITests --only StatScoutUITests/StatScoutIPadUITests --device "iPad Pro 13-inch (M5)"
```

Attachments are named `<orientation>_<n>_<screen>`; read `manifest.json` in
`~/.gh-sim/results/<id>/attachments` to map the UUID file names back.

Landscape frames from the UI test come back turned 90 degrees. The
`*_screen.png` attachments (XCUIScreen) turn upright with `sips -r 270`; the
plain `app.screenshot()` copies do not come out right. Rotate before judging
the layout.
