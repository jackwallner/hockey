#!/usr/bin/env python3
"""Step 3: search_app_store for each Astro store (native head term)."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import call, ping

MCP_URL = "http://127.0.0.1:8089/mcp"
STORES_JSON = Path(__file__).parent / "astro-stores-2026.json"
OUT = Path(__file__).parent / "astro-competitor-research.json"

HEAD_TERMS: dict[str, str] = {
    "us": "baseball statcast",
    "gb": "baseball statcast",
    "ca": "mlb statcast",
    "au": "baseball stats",
    "de": "baseball statistiken",
    "fr": "statistiques baseball",
    "es": "estadísticas béisbol",
    "mx": "estadísticas béisbol",
    "br": "estatísticas beisebol",
    "jp": "野球 スタッツ",
    "kr": "야구 통계",
    "cn": "棒球 数据",
    "tw": "棒球 統計",
    "it": "statistiche baseball",
    "nl": "honkbal statistieken",
    "pl": "statystyki baseball",
    "ru": "бейсбол статистика",
    "tr": "beyzbol istatistik",
    "sa": "بيسبول إحصائيات",
    "in": "baseball stats app",
    "th": "เบสบอล สถิติ",
    "vi": "bong chay thong ke",
    "id": "statistik baseball",
}

DEFAULT_TERM = "baseball statcast"


def head_term(store: str) -> str:
    return HEAD_TERMS.get(store, DEFAULT_TERM)


def main() -> None:
    if not ping(MCP_URL):
        raise SystemExit("error: Astro MCP not reachable")
    stores = json.loads(STORES_JSON.read_text())["stores"]
    results: dict = {"scannedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "stores": {}}
    for i, entry in enumerate(stores):
        code = entry["code"]
        term = head_term(code)
        try:
            hits = call(MCP_URL, "search_app_store", {"query": term, "store": code, "limit": 5})
            top = []
            if isinstance(hits, list):
                for h in hits[:5]:
                    if isinstance(h, dict):
                        top.append(
                            {
                                "name": h.get("name") or h.get("title"),
                                "subtitle": h.get("subtitle"),
                                "bundleId": h.get("bundleId"),
                            }
                        )
            results["stores"][code] = {"term": term, "competitors": top}
            print(f"{code}: {term} → {len(top)} hits")
        except Exception as e:
            results["stores"][code] = {"term": term, "error": str(e)}
            print(f"{code}: ERROR {e}", file=sys.stderr)
        if i < len(stores) - 1:
            time.sleep(1.1)
    OUT.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
