#!/usr/bin/env python3
"""Apply optimized native keywords/subtitles for StatScout fastlane metadata (go pipeline).

Dedupes keywords against each locale's name + subtitle (Apple indexes all three;
repeats waste the 100-char keyword field — see ASC ASO Assist).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
BRAND_NAME = "Baseball Savvy StatScout"

# Raw lists; dedupe_keywords strips tokens already in name/subtitle at write time.
KEYWORDS: dict[str, str] = {
    "en-US": "statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs,fantasy,metrics,leaderboard,comparison,hardhit,launch,xslg,xba,whiff,sabermetrics",
    "en-GB": "statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs,fantasy,metrics,leaderboard,comparison,hardhit,launch,xslg,xba,whiff,sabermetrics",
    "en-AU": "statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs,fantasy,metrics,leaderboard,comparison,hardhit,launch,xslg,xba,whiff,sabermetrics",
    "en-CA": "statcast,savant,mlb,wrc,xwoba,oaa,barrel,sprint,velo,scout,sports,strike,percentile,wrcplus,dfs,fantasy,metrics,leaderboard,comparison,hardhit,launch,xslg,xba,whiff,sabermetrics",
    "de-DE": "statcast,savant,mlb,baseball,statistik,perzentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,metriken,vergleich,leaderboard",
    "fr-FR": "statcast,savant,mlb,baseball,stats,percentile,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métriques,classement,comparaison",
    "fr-CA": "statcast,savant,mlb,baseball,stats,percentile,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métriques,classement,comparaison",
    "es-ES": "statcast,savant,mlb,béisbol,estadística,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métricas,ranking,comparación",
    "es-MX": "statcast,savant,mlb,béisbol,estadística,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métricas,ranking,comparación",
    "ca": "statcast,savant,mlb,beisbol,estadística,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,mètriques,rànquing",
    "it": "statcast,savant,mlb,baseball,statistiche,percentile,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,metriche,classifica,confronto",
    "pt-BR": "statcast,savant,mlb,beisebol,estatística,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métricas,ranking,comparação",
    "pt-PT": "statcast,savant,mlb,beisebol,estatística,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,métricas,ranking,comparação",
    "nl-NL": "statcast,savant,mlb,honkbal,statistiek,percentiel,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,metrics,ranglijst,vergelijking",
    "pl": "statcast,savant,mlb,baseball,statystyki,percentyl,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,metryki,ranking,porównanie",
    "sv": "statcast,savant,mlb,baseboll,statistik,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistik,ranking,jämförelse",
    "da": "statcast,savant,mlb,baseball,statistik,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistik,ranking,sammenligning",
    "no": "statcast,savant,mlb,baseball,statistikk,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistikk,ranking,sammenligning",
    "fi": "statcast,savant,mlb,baseball,tilastot,prosentti,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,tilastot,ranking,vertailu",
    "cs": "statcast,savant,mlb,baseball,statistiky,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistiky,žebříček,porovnání",
    "sk": "statcast,savant,mlb,baseball,štatistiky,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,štatistiky,rebríček,porovnanie",
    "hu": "statcast,savant,mlb,baseball,statisztika,százalék,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statisztika,rangsor,összehasonlítás",
    "ro": "statcast,savant,mlb,baseball,statistici,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistici,clasament,comparare",
    "hr": "statcast,savant,mlb,bejzbol,statistika,postotak,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,statistika,rang,usporedba",
    "el": "statcast,savant,mlb,μπέιζμπολ,στατιστικά,ποσοστό,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,στατιστικά,κατάταξη",
    "tr": "statcast,savant,mlb,beyzbol,istatistik,yüzdelik,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,istatistik,sıralama,karşılaştırma",
    "ru": "statcast,savant,mlb,бейсбол,статистика,процентиль,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,статистика,рейтинг,сравнение",
    "uk": "statcast,savant,mlb,бейсбол,статистика,відсоток,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,статистика,рейтинг,порівняння",
    "ja": "statcast,savant,mlb,野球,統計,パーセンタイル,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,ランキング,比較,メトリクス",
    "ko": "statcast,savant,mlb,야구,통계,백분위,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,순위,비교,메트릭",
    "zh-Hans": "statcast,savant,mlb,棒球,统计,百分位,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,排名,对比,指标",
    "zh-Hant": "statcast,savant,mlb,棒球,統計,百分位,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,排名,對比,指標",
    "ar-SA": "statcast,savant,mlb,بيسبول,إحصائيات,نسبة,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,تصنيف,مقارنة",
    "he": "statcast,savant,mlb,בייסבול,סטטיסטיקה,אחוזון,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,דירוג,השוואה",
    "hi": "statcast,savant,mlb,बेसबॉल,आंकड़े,प्रतिशत,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,रैंकिंग,तुलना",
    "th": "statcast,savant,mlb,เบสบอล,สถิติ,เปอร์เซ็นไทล์,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,อันดับ,เปรียบเทียบ",
    "vi": "statcast,savant,mlb,bongchay,thongke,phantram,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,xephang,soanh",
    "id": "statcast,savant,mlb,baseball,statistik,persentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,peringkat,perbandingan",
    "ms": "statcast,savant,mlb,besbol,statistik,peratus,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,kedudukan,perbandingan",
    "bn-BD": "statcast,savant,mlb,বেসবল,পরিসংখ্যান,শতাংশ,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,র‍্যাঙ্কিং",
    "gu-IN": "statcast,savant,mlb,બેસબોલ,આંકડા,ટકાવારી,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,રેન્કિંગ",
    "kn-IN": "statcast,savant,mlb,ಬೇಸ್ಬಾಲ್,ಅಂಕಿಅಂಶ,ಶೇಕಡಾ,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,ಶ್ರೇಯಾಂಕ",
    "ml-IN": "statcast,savant,mlb,ബേസ്ബോൾ,സ്ഥിതിവിവരം,ശതമാനം,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,റാങ്കിംഗ്",
    "mr-IN": "statcast,savant,mlb,बेसबॉल,आकडेवारी,टक्केवारी,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,रँकिंग",
    "or-IN": "statcast,savant,mlb,ବେସବଲ,ପରିସଂଖ୍ୟା,ଶତାଂଶ,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,ର୍ୟାଙ୍କିଂ",
    "pa-IN": "statcast,savant,mlb,ਬੇਸਬਾਲ,ਅੰਕੜੇ,ਪ੍ਰਤੀਸ਼ਤ,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,ਰੈਂਕਿੰਗ",
    "ta-IN": "statcast,savant,mlb,பேஸ்பால்,புள்ளிவிவரம்,சதவீதம்,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,தரவரிசை",
    "te-IN": "statcast,savant,mlb,బేస్బాల్,గణాంకాలు,శాతం,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,ర్యాంకింగ్",
    "ur-PK": "statcast,savant,mlb,بیسبال,اعداد,فیصد,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,درجہ",
    "sl-SI": "statcast,savant,mlb,baseball,statistika,percentil,wrc,xwoba,oaa,barrel,sprint,velo,scout,strike,dfs,fantasy,lestvica,primerjava",
}

SUBTITLES: dict[str, str] = {
    "en-US": "MLB Statcast Percentiles",
    "en-GB": "MLB Statcast Percentiles",
    "en-AU": "MLB Statcast Percentiles",
    "en-CA": "MLB Statcast Percentiles",
    "de-DE": "MLB Statcast Perzentile",
    "fr-FR": "Percentiles MLB Statcast",
    "fr-CA": "Percentiles MLB Statcast",
    "es-ES": "Percentiles MLB Statcast",
    "es-MX": "Percentiles MLB Statcast",
    "ca": "Percentils MLB Statcast",
    "it": "Percentili MLB Statcast",
    "pt-BR": "Percentis MLB Statcast",
    "pt-PT": "Percentis MLB Statcast",
    "nl-NL": "MLB Statcast Percentielen",
    "pl": "Percentyle MLB Statcast",
    "ja": "MLBスタットキャスト順位",
    "ko": "MLB 스탯캐스트 백분위",
    "zh-Hans": "MLB Statcast百分位",
    "zh-Hant": "MLB Statcast百分位",
    "ru": "Процентили MLB Statcast",
    "uk": "Процентилі MLB Statcast",
    "ar-SA": "نسب MLB Statcast",
    "hi": "MLB Statcast प्रतिशत",
    "th": "เปอร์เซ็นไทล์ MLB",
    "tr": "MLB Statcast Yüzdelik",
    "sv": "MLB Statcast Percentiler",
    "da": "MLB Statcast Percentiler",
    "no": "MLB Statcast Percentiler",
    "fi": "MLB Statcast Prosentit",
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[a-z0-9]+", text, flags=re.I):
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
        if any(kw == t or (len(kw) >= 4 and kw in t) or (len(t) >= 4 and t in kw) for t in indexed):
            continue
        kept.append(kw)
    return ",".join(kept)


def trim_keywords(s: str, limit: int = 100) -> str:
    s = s.replace(" ", "")
    if len(s) <= limit:
        return s
    parts = s.split(",")
    while parts and len(",".join(parts)) > limit:
        parts.pop()
    return ",".join(parts)


def trim_subtitle(s: str, limit: int = 30) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        if loc not in KEYWORDS:
            continue
        kw_path = loc_dir / "keywords.txt"
        sub_path = loc_dir / "subtitle.txt"
        name_path = loc_dir / "name.txt"
        old_kw = kw_path.read_text(encoding="utf-8").strip() if kw_path.exists() else ""
        old_sub = sub_path.read_text(encoding="utf-8").strip() if sub_path.exists() else ""
        name = name_path.read_text(encoding="utf-8").strip() if name_path.exists() else BRAND_NAME
        if name_path.exists():
            name_path.write_text(trim_subtitle(BRAND_NAME) + "\n", encoding="utf-8")
        sub_for_dedupe = SUBTITLES.get(loc, old_sub)
        if loc in SUBTITLES:
            new_sub = trim_subtitle(SUBTITLES[loc])
            sub_path.write_text(new_sub + "\n", encoding="utf-8")
        elif loc.startswith("en-"):
            new_sub = trim_subtitle("MLB Statcast Percentiles")
            sub_path.write_text(new_sub + "\n", encoding="utf-8")
        else:
            new_sub = old_sub
        new_kw = trim_keywords(dedupe_keywords(name, sub_for_dedupe, KEYWORDS[loc]))
        kw_path.write_text(new_kw + "\n", encoding="utf-8")
        report[loc] = {
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "subtitle": {"old": old_sub, "new": new_sub},
            "name": name,
        }
    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(report)} locales → {out}")
    print("en-US sample:", report.get("en-US", {}).get("keywords", {}).get("new", ""))


if __name__ == "__main__":
    main()
