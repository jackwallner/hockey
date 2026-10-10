#!/usr/bin/env python3
"""Configure the nonlocalized Hockey Edge: Puck StatScout App Store listing fields."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.hockey"
APP_NAME = "Hockey Edge: Puck StatScout"
# Age-rating answers are copied from the live football sibling, whose record
# answers every question the same way this app does.
AGE_TEMPLATE_BUNDLE_ID = os.environ.get(
    "ASC_AGE_TEMPLATE_BUNDLE_ID", "com.jackwallner.football"
)
REVIEW_NOTES = """The App Store name is Hockey Edge: Puck StatScout. The app is named Hockey StatScout in-app and StatScout on the Home Screen. It is a read-only NHL statistics viewer with no accounts or sign-in.

Core flow:
1. Launch the app and open the Stats tab for current-season player rankings.
2. Filter by Forwards, Defensemen or Goalies, choose a statistic, and open a player profile for percentile rankings, standard stats, bio and game log.
3. Open Games for the nightly schedule, final scores, box scores and the expected-goals breakdown of each game.
4. Open Teams for records, standings, team power ratings and projected margins.
5. Following, player comparisons, Trends, Recent Form and historical views are available from their tabs or player/team pages.

StatScout+ features (IAP via RevenueCat):
- Trends, Recent Form, player comparisons, team scouting, historical seasons back to 2008-09, and All-Time career percentiles
- Restore Purchases is available in Settings; purchases can be tested with an Apple sandbox account

Data: expected goals and shot data from MoneyPuck.com (public, attributed in Settings), schedule, box scores and bios from public NHL data, refreshed after every night's games. Not affiliated with the NHL, any NHL team, the NHLPA or MoneyPuck. No league, team, or player imagery is used.

The app has no accounts, social features, live scores, play-by-play, betting odds, wagers, or fantasy team management. Game projections are informational estimates, not betting odds."""


def review_phone() -> str:
    """The App Review contact number, which never belongs in a public repo.

    Sourced from ASC_REVIEW_PHONE, or from the shell-sourced
    ``~/.hockey_credentials`` that the other scripts here already read.
    """
    value = os.environ.get("ASC_REVIEW_PHONE")
    if value:
        return value.strip()
    path = Path.home() / ".hockey_credentials"
    if path.exists():
        for line in path.read_text().splitlines():
            key, _, raw = line.partition("=")
            key = key.strip().removeprefix("export ").strip()
            if key == "ASC_REVIEW_PHONE":
                return raw.strip().strip('"').strip("'")
    raise SystemExit(
        "error: set ASC_REVIEW_PHONE, or add it to ~/.hockey_credentials.\n"
        "The App Review contact number is deliberately not stored in this repo."
    )


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: the app needs an editable app info and version")

    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "copyright": "2026 Jack Wallner",
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    age = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    template_app = A.find_app(client, AGE_TEMPLATE_BUNDLE_ID)
    template_info = A.find_editable_app_info(client, template_app["id"])
    template_age = client.get(
        f"/appInfos/{template_info['id']}/ageRatingDeclaration"
    )["data"]["attributes"]
    attrs = {key: value for key, value in template_age.items() if value is not None}
    attrs.pop("ageRatingOverride", None)
    attrs.update(
        {
            "medicalOrTreatmentInformation": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        }
    )
    client.patch(
        f"/ageRatingDeclarations/{age['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age["id"],
                "attributes": attrs,
            }
        },
    )

    review = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attributes = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": review_phone(),
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if review:
        client.patch(
            f"/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
    print(f"configured {APP_NAME} ({app['id']})")


if __name__ == "__main__":
    main()
