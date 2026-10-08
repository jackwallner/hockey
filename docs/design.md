---
version: alpha
name: StatScout Pro
description: RevenueCat paywall & entitlements for StatScout baseball analytics.
colors:
  primary: "#1A1A2E"
  secondary: "#16213E"
  tertiary: "#0F3460"
  accent: "#E94560"
  neutral: "#F5F5F7"
  surface: "#FFFFFF"
  on-primary: "#FFFFFF"
  on-accent: "#FFFFFF"
typography:
  display:
    fontFamily: SF Pro Display
    fontSize: 2rem
    fontWeight: 700
  h1:
    fontFamily: SF Pro Display
    fontSize: 1.5rem
    fontWeight: 600
  body:
    fontFamily: SF Pro Text
    fontSize: 0.94rem
    lineHeight: 1.5
  label:
    fontFamily: SF Pro Text
    fontSize: 0.81rem
    fontWeight: 500
    letterSpacing: "0.01em"
  caption:
    fontFamily: SF Pro Text
    fontSize: 0.75rem
    lineHeight: 1.4
rounded:
  sm: 8px
  md: 12px
  lg: 20px
  xl: 28px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
components:
  paywall-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    borderColor: "{colors.secondary}"
    rounded: "{rounded.md}"
    padding: 20px
  paywall-cta:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.xl}"
    padding: 16px 24px
    fontWeight: 600
  product-option:
    backgroundColor: "{colors.surface}"
    borderColor: "{colors.neutral}"
    rounded: "{rounded.sm}"
    padding: 12px 16px
  badge-best-value:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.sm}"
    padding: 4px 10px
  feature-row:
    iconColor: "{colors.tertiary}"
    textColor: "{colors.primary}"
    padding: 8px 0
---

## Overview

StatScout Pro is a three-tier IAP model (Monthly, Yearly, Lifetime) managed through RevenueCat for a baseball analytics iOS app. The paywall gates historical Statcast data, player comparisons, and advanced metrics behind a `StatScout Pro` entitlement.

## Products

| Product ID | Type | Trial |
|---|---|---|
| `com.jackwallner.baseball.pro.monthly` | Auto-renewing subscription | No |
| `com.jackwallner.baseball.pro.yearly` | Auto-renewing subscription | Yes (free trial) |
| `com.jackwallner.baseball.pro` | Non-consumable lifetime | N/A |

## Entitlements

- **Primary:** `StatScout Pro` — attached to all three products
- **Fallback:** `pro` — same attachment, safety fallback
- **Check logic:** `!entitlements.active.isEmpty` (any active entitlement = Pro)

## Offerings

Single `"default"` offering with three packages: **Monthly**, **Yearly** (default, best value), **Lifetime**. The app fetches via `Purchases.shared.offerings()`, falls back to `current` if `"default"` is missing.

## Paywall UI

Full-screen modal (`PaywallView.swift`) with product radio-button cards, dynamic CTA label, legal footer, restore button, and success alert. Yearly is pre-selected with "Best Value" badge.

### CTA Label States

- `"Start Free Trial"` — yearly, trial eligible
- `"Subscribe — $X.XX/mo"` — yearly/monthly, no trial available
- `"Buy Lifetime — $XX.XX"` — lifetime selected

## Feature Gating

| Feature | Gating |
|---|---|
| Historical seasons (≠ current year) | Locked — shows paywall |
| Player Comparisons tab | Locked — full paywall |
| Percentiles & Year Compare tabs | Hidden for free users |
| Teams & Metrics root tabs | Bounce to Dashboard + paywall |

> **Known leaks:** TeamsView, MetricLeadersView, and StandardStatsLeadersView show Pro banners but aren't actually feature-gated.

## Architecture

```
StatScoutApp.swift
  └─ @StateObject StoreService.shared       ← singleton, @MainActor
       └─ .environmentObject(store)          ← injected into view tree

StoreService (ObservableObject)
  ├─ Purchases.configure(apiKey:)            ← app init
  ├─ offerings() → "default" offering
  ├─ purchase(package:) → PurchaseState
  ├─ restorePurchases()
  ├─ PurchasesDelegate → live customerInfo
  └─ @Published: products, customerInfo, isPro, purchaseInFlight
```

Customer info refreshes on every foreground event.

## Configuration

| Key | Value |
|---|---|
| SDK | RevenueCat iOS v5.72+ (SPM: `purchases-ios-spm`) |
| API Key | `appl_qNlZGCCfGWBTsvcxlqYSNCtRupx` |
| Debug logging | `Purchases.logLevel = .debug` in DEBUG builds |
| StoreKit config | None (no `.storekit` for local testing) |

## RC Dashboard Checklist

- [ ] 3 products: `.monthly`, `.yearly`, `.pro`
- [ ] Entitlement `StatScout Pro` + fallback `pro`
- [ ] `"default"` offering with Monthly, Yearly, Lifetime packages
- [ ] Yearly = default package, introductory offer enabled
- [ ] Product IDs match App Store Connect exactly
- [ ] API key has correct bundle ID permissions
