from __future__ import annotations

import unittest
from html.parser import HTMLParser
from pathlib import Path


DOCS = Path(__file__).resolve().parents[2] / "docs"
APP_STORE_URL = "https://apps.apple.com/app/id6820644691"


class DownloadParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.buttons: list[tuple[str, dict[str, str | None]]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if "download-btn" in (attributes.get("class") or "").split():
            self.buttons.append((tag, attributes))


class LandingPageTests(unittest.TestCase):
    def test_both_download_buttons_open_the_live_app_store_listing(self) -> None:
        html = (DOCS / "index.html").read_text()
        parser = DownloadParser()
        parser.feed(html)

        self.assertEqual(len(parser.buttons), 2)
        for index, (tag, attributes) in enumerate(parser.buttons):
            with self.subTest(button=index):
                self.assertEqual(tag, "a")
                self.assertEqual(attributes.get("href"), APP_STORE_URL)
                self.assertNotEqual(attributes.get("aria-disabled"), "true")
        self.assertNotIn("Coming soon to the App Store", html)

    def test_xg_article_does_not_describe_the_live_app_as_upcoming(self) -> None:
        html = (DOCS / "what-is-xg-in-hockey.html").read_text()
        self.assertNotIn("coming to the App Store", html)


if __name__ == "__main__":
    unittest.main()
