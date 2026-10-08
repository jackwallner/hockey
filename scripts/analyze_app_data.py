#!/usr/bin/env python3
"""Replicate StatScout's per-view filter+sort against live data to surface
outliers/mismatches a user would see. Mirrors DashboardViewModel logic."""
import os
import sys
import json
import urllib.request

URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_ANON_KEY"]


def fetch_all(season="eq.2026"):
    rows, offset, page_size = [], 0, 1000
    while True:
        q = (
            f"{URL}/rest/v1/player_snapshots?select=*&season={season}"
            f"&order=id.asc&limit={page_size}&offset={offset}"
        )
        req = urllib.request.Request(
            q, headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"}
        )
        page = json.load(urllib.request.urlopen(req))
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def num(s):
    try:
        s = str(s).strip()
        if s.startswith("."):
            s = "0" + s
        return float("".join(c for c in s if c.isdigit() or c in ".-") or 0)
    except Exception:
        return 0.0


def cat_metrics(p, category):
    return [m for m in p["metrics"] if m.get("category") == category]


def matches_type(p, category):
    t = (p.get("player_type") or "").lower()
    if category == "Hitting":
        return t != "pitcher"
    if category == "Pitching":
        return t in ("pitcher", "two_way")
    return True


def percentile_for(p, category):
    cms = cat_metrics(p, category)
    if not cms:
        return None
    return round(sum(m["percentile"] for m in cms) / len(cms))


def metric(p, label, category):
    for m in p["metrics"]:
        if m["label"] == label and m.get("category") == category:
            return m
    return None


PRIORITY = {
    "Hitting": ["xwOBA", "xSLG", "xBA"],
    "Pitching": ["xwOBA", "K%", "Barrel%", "Whiff%", "Chase%"],
}


def dashboard(players, category):
    """Default qualifier = .qualified -> has any metric in category."""
    fp = [
        p
        for p in players
        if cat_metrics(p, category)
        and matches_type(p, category)
    ]
    sort_label = next(
        (
            lbl
            for lbl in PRIORITY[category]
            if any(metric(p, lbl, category) for p in fp)
        ),
        None,
    )

    def score(p):
        if sort_label and metric(p, sort_label, category):
            return metric(p, sort_label, category)["percentile"]
        return percentile_for(p, category) or 0

    return sort_label, sorted(fp, key=score, reverse=True)


def report(players):
    print(f"Total 2026 rows: {len(players)}")
    types = {}
    for p in players:
        types[p.get("player_type")] = types.get(p.get("player_type"), 0) + 1
    print(f"player_type: {types}\n")

    for category in ("Hitting", "Pitching"):
        sort_label, board = dashboard(players, category)
        print(f"=== DASHBOARD · {category} (sort={sort_label}, qualified) ===")
        print(f"rows shown: {len(board)}")

        # Outlier 1: wrong-type leakage
        leak = [
            p
            for p in board
            if (category == "Hitting" and (p.get("player_type") or "").lower() == "pitcher")
            or (category == "Pitching" and (p.get("player_type") or "").lower() == "batter")
        ]
        print(f"  [type leak] {len(leak)}: {[p['name'] for p in leak[:8]]}")

        # Outlier 2: percentile vs raw value inconsistency for the sort metric
        if sort_label:
            vals = []
            for p in board:
                m = metric(p, sort_label, category)
                if m:
                    vals.append((p["name"], m["percentile"], num(m.get("value", ""))))
            # higher percentile should track better raw value. For Hitting xwOBA
            # higher raw = better; for Pitching xwOBA-against lower raw = better.
            inversions = []
            for i in range(len(vals) - 1):
                n1, pc1, rv1 = vals[i]
                n2, pc2, rv2 = vals[i + 1]
                if pc1 == pc2 or rv1 == 0 or rv2 == 0:
                    continue
                if category == "Hitting" and pc1 > pc2 and rv1 < rv2:
                    inversions.append((n1, pc1, rv1, n2, pc2, rv2))
                if category == "Pitching" and pc1 > pc2 and rv1 > rv2:
                    inversions.append((n1, pc1, rv1, n2, pc2, rv2))
            print(f"  [pctile vs raw {sort_label} inversions] {len(inversions)}")
            for inv in inversions[:6]:
                print(f"     {inv[0]} {inv[1]}p/{inv[2]} ABOVE {inv[3]} {inv[4]}p/{inv[5]}")

        # Outlier 3: top 10 sanity
        print("  top 10:")
        for i, p in enumerate(board[:10], 1):
            m = metric(p, sort_label, category) if sort_label else None
            mv = f"{m['value']} ({m['percentile']}p)" if m else "—"
            print(
                f"   {i:2d}. {p['name']:<22} {p['team']:<4} "
                f"{p.get('player_type'):<8} {sort_label}={mv}"
            )
        print()

    # Box Score leaders (StandardStatsLeadersView): hitting AVG desc, pitching ERA asc
    print("=== BOX SCORE · Hitting AVG (desc) ===")
    hb = [
        p
        for p in players
        if p.get("standard_stats")
        and matches_type(p, "Hitting")
        and any(s["label"] == "AVG" for s in p["standard_stats"])
    ]
    hb.sort(
        key=lambda p: num(next(s["value"] for s in p["standard_stats"] if s["label"] == "AVG")),
        reverse=True,
    )
    for i, p in enumerate(hb[:10], 1):
        avg = next(s["value"] for s in p["standard_stats"] if s["label"] == "AVG")
        ab = next((s["value"] for s in p["standard_stats"] if s["label"] in ("AB", "PA")), "?")
        print(f"   {i:2d}. {p['name']:<22} {p['team']:<4} {p.get('player_type'):<8} AVG={avg} AB/PA={ab}")
    print("   (watch: tiny-sample .999 AVGs from 1-2 AB)")
    print()

    print("=== BOX SCORE · Pitching ERA (asc) ===")
    pb = [
        p
        for p in players
        if p.get("standard_stats")
        and matches_type(p, "Pitching")
        and any(s["label"] == "ERA" for s in p["standard_stats"])
    ]
    pb.sort(key=lambda p: num(next(s["value"] for s in p["standard_stats"] if s["label"] == "ERA")))
    for i, p in enumerate(pb[:10], 1):
        era = next(s["value"] for s in p["standard_stats"] if s["label"] == "ERA")
        ip = next((s["value"] for s in p["standard_stats"] if s["label"] == "IP"), "?")
        print(f"   {i:2d}. {p['name']:<22} {p['team']:<4} {p.get('player_type'):<8} ERA={era} IP={ip}")
    print("   (watch: 0.00 ERA from <2 IP mop-up)")


if __name__ == "__main__":
    report(fetch_all())
