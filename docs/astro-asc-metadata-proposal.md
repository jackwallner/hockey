# ASC metadata proposal — name, subtitle, keywords

Apple limits (en-US):

| Field | Limit | Format |
|-------|-------|--------|
| **Name** | 30 chars | Visible title; highest weight |
| **Subtitle** | 30 chars | Shown under name; high weight |
| **Keywords** | **100 chars** | `word,word,word` — **no spaces** after commas |

Character counts below are exact (commas count).

---

## Keywords — does the recommendation fit?

| Set | Chars | Fits? |
|-----|-------|-------|
| **Current (live)** | **100** | At limit |
| Earlier doc proposal (`statcast,savant,mlb,wRC,xwOBA,...`) | 72 | Yes — 28 chars unused |
| **Recommended v3** | **95** | Yes — 5 chars headroom |

### Current (100/100)

```
sabermetric,analytic,scout,sports,statcast,velo,wRC,strike,statistic,savant,barrel,sprint,OAA,expect
```

Problems: wastes space on low-rank tokens (`analytic`, `statistic`, `expect`); missing **`mlb`** (Astro pop **62**).

### Recommended keywords (95/100)

```
statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs
```

| Token | Why |
|-------|-----|
| statcast, savant | Core discovery (#95 savant); subtitle can reinforce |
| **mlb** | Highest pop (62) — must be in keyword field |
| wrc, xwoba, oaa | Metrics you rank on (oaa #14) |
| barrel, sprint, velo | ASC + Astro high-pop fight list |
| scout, sports, strike | High pop; broad but indexed |
| percentile | Matches feature + subtitle |
| wrcplus, dfs | Fantasy/analyst audience |

Dropped vs earlier 72-char draft: `fantasy` as standalone (kept `dfs`), `stats` (redundant with name/subtitle).

---

## Name — should we change it?

**Recommendation: keep the current name** unless you are rebranding.

```
Baseball Savvy StatScout   (24/30)
```

| Reason | Detail |
|--------|--------|
| Rankings | #1 for `statscout`, `baseball savvy statscout`, `stat scout` |
| Brand | “StatScout” is the product name users search |
| Risk | Renaming can disturb branded rankings for weeks |

### If you still want to test name (≤30 chars)

| Option | Chars | Tradeoff |
|--------|-------|----------|
| `StatScout - Baseball Savant` | 27 | Leads with brand; adds “savant” |
| `StatScout: MLB Savant Stats` | 25 | Adds MLB + savant; drops “Savvy” |
| `MLB StatScout - Savvy Stats` | 27 | MLB-first; may help `mlb` generic |

Do **not** change name and subtitle in the same release — isolate variables.

---

## Subtitle — yes, optimize this

Current (27/30):

```
Percentile Rankings & Stats
```

Ranks #64 for `percentile rankings` — good, but misses **mlb** (pop 62) and **savant** / **statcast**.

### Recommended subtitle (24/30)

```
MLB Statcast Percentiles
```

- Packs **MLB** + **Statcast** + core feature in 24 characters  
- Pairs with keyword field (`mlb`, `statcast`, `percentile`)

### Alternate A/B (pick one test)

| Subtitle | Chars | Best for |
|----------|-------|----------|
| `Statcast Savant Percentiles` | 27 | Pushing **savant** (#95) + statcast |
| `Savant & MLB Percentile Stats` | 29 | Both savant + MLB in one line |
| `MLB Savant Percentile Stats` | 27 | Savant + MLB + “stats” |

---

## Suggested upload bundle (one experiment)

| Field | Value |
|-------|-------|
| Name | `Baseball Savvy StatScout` *(unchanged)* |
| Subtitle | `MLB Statcast Percentiles` |
| Keywords | `statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs` |

After editing `fastlane/metadata/en-US/{name,subtitle,keywords}.txt`:

```bash
./scripts/upload-appstore-metadata.sh
```

Wait **7–14 days**, then `./scripts/astro-optimize.sh` and compare Astro ranks for `mlb`, `statcast`, `savant`, `percentile`.

---

## What Astro tracks vs ASC field

- **ASC keywords** = 100-char indexed field (this doc).  
- **Astro** = separate search phrases (53 terms in `scripts/astro-keywords-us.json`).  
Both should align on **mlb**, **savant**, **statcast**, **percentile**, but Astro can track long phrases ASC cannot fit (e.g. `spray chart`, `player comparison`).
