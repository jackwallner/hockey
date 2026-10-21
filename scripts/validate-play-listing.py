#!/usr/bin/env python3
"""Validate Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title, no medical claims), the StatScout brand in the title, the Google
Play billing paragraph, the policy links, the MoneyPuck/NHL attribution, and
that every non-English description says the app itself is in English.
Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--root DIR]
"""
from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "android/play-assets/metadata/android"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
# The word for "English" in each listing language, used to prove the
# description says the Android app is not localized.
ENGLISH_WORD = {
    "de": "Englisch", "fr": "anglais", "es": "inglés", "pt": "inglês", "it": "inglese",
    "nl": "Engels", "sv": "engelska", "no": "engelsk", "da": "engelsk", "fi": "englanni",
    "pl": "angielsk", "cs": "angličtin", "sk": "angličtin", "sl": "angleščin",
    "hr": "engleskom", "hu": "angol", "ro": "engleză", "el": "αγγλικά", "tr": "İngilizce",
    "ru": "английском", "uk": "англійською", "ar": "الإنجليزية", "iw": "באנגלית",
    "hi": "अंग्रेज", "bn": "ইংরেজি", "mr": "इंग्रजी", "ta": "ஆங்கில", "te": "ఇంగ్లీష్",
    "kn": "ಇಂಗ್ಲಿಷ್", "ml": "ഇംഗ്ലീഷ", "id": "bahasa Inggris", "ms": "bahasa Inggeris",
    "th": "ภาษาอังกฤษ", "vi": "tiếng Anh", "ja": "英語", "ko": "영어", "zh": "英",
    "ca": "anglès",
}
TITLE_BANNED = re.compile(r"\b(free|best|top|#1|new|sale)\b", re.I)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"\b(?:Apple|App Store|iPhone|iPad|iCloud|Apple Watch)\b", re.I)
MEDICAL = re.compile(r"\b(treat|treats|cure|cures|diagnose|diagnoses)\b", re.I)
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")
REQUIRED_URLS = (
    "https://jackwallner.github.io/hockey/android-privacy.html",
    "https://jackwallner.github.io/hockey/android-terms.html",
)


def nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text)


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def check(locale_dir: Path) -> list[str]:
    errs: list[str] = []
    loc = locale_dir.name
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        p = locale_dir / name
        if not p.exists():
            errs.append(f"missing {name}")
            continue
        text = read(p)
        n = len(text)
        if n == 0 or n > limit:
            errs.append(f"{name} {n}/{limit}")
        if "—" in text:
            errs.append(f"{name} has an em dash")
        if re.search("[­​﻿]", text):
            errs.append(f"{name} has an invisible character")
        if PRICE.search(text):
            errs.append(f"{name} looks like it has a price: {PRICE.search(text).group(0)!r}")
        if APPLE.search(URL_OK.sub("", text)):
            errs.append(f"{name} mentions Apple wording: {APPLE.search(text).group(0)!r}")
        if MEDICAL.search(text):
            errs.append(f"{name} makes a medical claim: {MEDICAL.search(text).group(0)!r}")
        if name != "full_description.txt" and "\n" in text:
            errs.append(f"{name} spans lines")
    title = read(locale_dir / "title.txt")
    if TITLE_BANNED.search(title):
        errs.append(f"title has a promo word: {title!r}")
    if "StatScout" not in title:
        errs.append(f"title drops the StatScout brand: {title!r}")
    full = read(locale_dir / "full_description.txt")
    if "Google Play" not in full:
        errs.append("full description lacks the Google Play billing paragraph")
    for url in REQUIRED_URLS:
        if url not in full:
            errs.append(f"full description lacks {url}")
    if "MoneyPuck" not in full or "NHL" not in full:
        errs.append("full description lacks the MoneyPuck/NHL attribution")
    lang = loc.split("-")[0]
    if lang != "en":
        word = ENGLISH_WORD.get(lang)
        if word is None:
            errs.append(f"no English-notice word known for {lang}")
        elif nfc(word).lower() not in nfc(full).lower():
            errs.append(f"full description does not say the app is in English ({word!r})")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    bad = 0
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    for d in dirs:
        errs = check(d)
        t, s, f = (read(d / n) for n in LIMITS)
        status = "OK " if not errs else "BAD"
        print(f"{status} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    print(f"\n{len(dirs)} locales, {bad} with problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
