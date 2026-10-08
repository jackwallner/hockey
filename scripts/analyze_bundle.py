#!/usr/bin/env python3
import json

with open('StatScout/Data/players-historical.json') as f:
    data = json.load(f)

print(f'Total rows (player-seasons): {len(data)}')

# Unique players
ids = {}
for p in data:
    pid = p['id']
    ids[pid] = ids.get(pid, 0) + 1

print(f'Unique players: {len(ids)}')
print(f'  1 season:  {sum(1 for v in ids.values() if v == 1)}')
print(f'  2 seasons: {sum(1 for v in ids.values() if v == 2)}')
print(f'  3 seasons: {sum(1 for v in ids.values() if v == 3)}')
print(f'  4 seasons: {sum(1 for v in ids.values() if v == 4)}')
print(f'  5+ seasons: {sum(1 for v in ids.values() if v >= 5)}')
print(f'  7+ seasons: {sum(1 for v in ids.values() if v >= 7)}')
print(f'  10+ seasons: {sum(1 for v in ids.values() if v >= 10)}')
print(f'  Max seasons: {max(ids.values())}')

# Metrics per player-season
metrics_counts = [len(p.get('metrics', []) or []) for p in data]
print(f'\nMetrics per player-season:')
print(f'  min: {min(metrics_counts)}')
print(f'  max: {max(metrics_counts)}')
print(f'  avg: {sum(metrics_counts)/len(metrics_counts):.1f}')
print(f'  0 metrics: {sum(1 for c in metrics_counts if c == 0)}')
print(f'  <5 metrics: {sum(1 for c in metrics_counts if c < 5)}')

# Standard stats per player-season
std_counts = [len(p.get('standard_stats', []) or []) for p in data]
print(f'\nStandard stats per player-season:')
print(f'  min: {min(std_counts)}')
print(f'  max: {max(std_counts)}')
print(f'  avg: {sum(std_counts)/len(std_counts):.1f}')
print(f'  0 stats: {sum(1 for c in std_counts if c == 0)}')

# Games data
game_counts = [len(p.get('games', []) or []) for p in data]
print(f'\nGames per player-season:')
print(f'  min: {min(game_counts)}')
print(f'  max: {max(game_counts)}')
print(f'  avg: {sum(game_counts)/len(game_counts):.1f}')
print(f'  0 games: {sum(1 for c in game_counts if c == 0)}')

# Total data points
total_metrics = sum(metrics_counts)
total_std = sum(std_counts)
print(f'\nTotal data points across all player-seasons:')
print(f'  Metrics: {total_metrics}')
print(f'  Standard stats: {total_std}')
print(f'  Total: {total_metrics + total_std}')
