# What Is xG in Hockey? Expected Goals and GSAx Explained

> Expected goals (xG) give every NHL shot a probability of scoring. See how xG works, how goalies are judged with GSAx, and what good numbers look like.

Web page: https://jackwallner.com/ios/hockey/what-is-xg-in-hockey.html

## What are expected goals (xG) in hockey? (And GSAx for goalies)

By Jack Wallner. Last updated October 28, 2026.

Expected goals (xG) is a hockey stat that gives every unblocked shot a probability of becoming a goal, based on things like where it was taken from and what happened just before. Add up those probabilities and you get the number of goals an average shooter would have scored. Goals saved above expected (GSAx) flips it around for goalies: expected goals faced minus goals actually allowed.

## How does xG work?

xG gives each unblocked shot a goal probability from its location, its type and what happened just before it, then adds those probabilities up. A shot is not a shot. A rebound in the slot goes in far more often than a long wrister from the point. MoneyPuck's glossary gives exactly that pair: a rebound shot in the slot may have a 50 percent chance of being a goal and so is worth 0.5 expected goals, while a shot from the blue line while short-handed may be worth 0.01.

The model behind it, according to MoneyPuck's methodology page, predicts the probability of each shot being a goal using the location of the shot, the shot type, the last event before the shot and how long before it happened, the time on ice of the players on both teams, the number of players on the ice, the shooter's handedness relative to the side of the ice, and whether the net is empty. Blocked shot attempts are valued at zero, and the value assumes an average shooter takes the shot, so shooting talent is not included.

A hypothetical game makes the idea concrete. A team takes three shots worth 0.45, 0.08 and 0.03 expected goals. Its game total is 0.56 xG, even if it scored zero or two. Over one game that tells you little. Over 82 it separates the teams that create good chances from the ones that get lucky.

## Why does hockey need xG?

Hockey needs xG because goals are rare, and a single bounce decides a lot of them. Shot counts alone miss quality, because a team can pile up point shots without testing the goalie. xG keeps the volume and adds the quality. That is why you will see it in team shares like xGF%, the share of 5-on-5 expected goals that went a team's way while a player was on the ice, where 50 percent is even.

## How do you tell if a shooter finishes above expected?

Compare a player's goals with his individual expected goals (ixG) to see whether he finished above or below what his shots deserved. In MoneyPuck's 2025-26 regular season data, Connor McDavid scored 48 goals against 43.6 ixG. Nathan MacKinnon scored 53 against 40.6, finishing 12 goals above what his chances were worth. A gap that big can be elite finishing, a hot season or both, and one year of data cannot say which.

## What is GSAx in hockey?

GSAx is expected goals against minus the actual number of goals the goalie has let in, as MoneyPuck defines it. A positive number means the goalie is stopping more goals than an average goalie would. Save percentage depends on the shots a goalie faces, and goalies on different teams face different shots. GSAx adjusts for that.

In the same 2025-26 data, Washington's Logan Thompson faced shots worth 169.3 expected goals and allowed 140, a GSAx of +29.3 across 1,587 shots on goal. St. Louis's Jordan Binnington faced 105.6 expected goals and allowed 128, a GSAx of -22.4.

## What is a good GSAx for a goalie?

In 2025-26, a typical goalie's season GSAx was about -0.8, the 90th percentile was +17.3 and the best was +29.3. I calculated the spread from MoneyPuck's 2025-26 regular season goalie file, using the 68 goalies with at least 1,000 minutes played.

| Metric (2025-26) | Weak (10th pct.) | Typical (median) | Strong (90th pct.) | Best |
| --- | --- | --- | --- | --- |
| GSAx (season total) | -12.9 | -0.8 | +17.3 | +29.3 (Logan Thompson) |
| GSAx per 60 minutes | -0.44 | -0.03 | +0.43 | +0.62 |

GSAx here is expected goals on shots on goal minus goals allowed, all situations. Percentiles are interpolated from the downloaded rows.

The median sits near zero because the average goalie is the baseline. A season total of +10 means a goalie saved about ten more goals than the average goalie would have behind the same shots.

## What are the limits of xG?

The model sees shot location and context, not everything on the ice. The inputs MoneyPuck lists do not include screens, pre-shot passing or goalie positioning. Models also get rebuilt: MoneyPuck says it retrained its model for 2026-27, on more than 289,000 shots from 2023-24 through 2025-26. Read xG as a good estimate of chance quality, not as a perfect one.

## How StatScout helps

[Hockey Edge: Puck StatScout](https://jackwallner.com/ios/hockey/) is an independent iPhone app, not affiliated with the NHL or MoneyPuck, built to rank every NHL skater and goalie on percentiles for ixG, GSAx, xGF% and related metrics, using MoneyPuck's data. Each metric shows as a color bar against the player's own position, so you can read a goalie's GSAx without knowing what a good total is.

## Frequently asked questions

### What is xG in hockey?

xG, or expected goals, is the probability that an unblocked shot becomes a goal, estimated from factors such as shot location, shot type and what happened just before it. Adding up the shot values gives the goals an average shooter would be expected to score.

### What is a good xG for a game?

There is no fixed threshold. Teams are usually compared by the share of expected goals they get, called xGF%, where 50 percent is even. Per shot, MoneyPuck's example values run from about 0.01 for a long short-handed shot to about 0.50 for a slot rebound.

### What does GSAx mean?

GSAx is goals saved above expected: the goals an average goalie would have allowed on the same shots, minus the goals the goalie actually allowed. A positive number means the goalie is outperforming the average.

### What is a good GSAx?

A strong season GSAx is about +17 or higher. In 2025-26, the median goalie with at least 1,000 minutes was about -0.8, and the 90th percentile was about +17.3. The best total was Logan Thompson at +29.3.

### Does xG account for shooter skill?

No. MoneyPuck's standard xG assumes an average shooter, so skill is not included. Goals above expected, goals minus ixG, is one way to see who finishes better or worse than average.

Related: [True shooting percentage explained (and usage rate)](https://jackwallner.com/ios/basketball/true-shooting-percentage-explained.html) and [What is EPA per play in football? (And what CPOE adds)](https://jackwallner.com/ios/football/what-is-epa-per-play.html).

## Sources

1. [MoneyPuck: About and How it Works (expected goals model)](https://moneypuck.com/about.htm)
2. [MoneyPuck: Glossary (expected goals, GSAx, xGF%)](https://moneypuck.com/glossary.htm)
3. [MoneyPuck: Data (season summary files)](https://moneypuck.com/data.htm)
