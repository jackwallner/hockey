from datetime import datetime, timezone

import ingest
import source_probe
from source_probe import (
    AssetProbe,
    AssetSpec,
    current_asset_specs,
    fingerprint_assets,
    parse_source_timestamp,
    probe_asset,
    probe_sources,
)


class Response:
    def __init__(self, status_code, headers=None):
        self.status_code = status_code
        self.headers = headers or {}


def generation(tag: str, status=200) -> Response:
    return Response(status, {
        "ETag": f'"{tag}"',
        "Last-Modified": "Thu, 08 Oct 2026 10:31:15 GMT",
        "Content-Length": "71654",
    })


class FakeHTTP:
    """HEAD responses by file name; anything unlisted is a 404."""

    def __init__(self, tag="one", missing=()):
        self.tag = tag
        self.missing = set(missing)
        self.requested: list[str] = []

    def head(self, url, *, timeout):
        self.requested.append(url)
        name = url.rsplit("/", 1)[-1]
        if any(token in url or token == name for token in self.missing):
            return Response(404)
        return generation(self.tag)


def probe(**kwargs):
    return probe_sources(2026, client=FakeHTTP(**kwargs))


def test_user_agent_matches_the_ingest_helpers():
    assert source_probe.USER_AGENT == ingest.USER_AGENT


def test_specs_cover_the_moneypuck_files_and_the_shots_zip():
    specs = {s.name: s for s in current_asset_specs(2026)}
    assert set(specs) == {
        "skaters_regular", "goalies_regular", "teams_regular",
        "skaters_playoffs", "goalies_playoffs", "teams_playoffs", "shots",
    }
    assert specs["skaters_regular"].url == (
        "https://moneypuck.com/moneypuck/playerData/seasonSummary/2026/regular/skaters.csv"
    )
    assert specs["teams_playoffs"].url.endswith("/2026/playoffs/teams.csv")
    assert specs["shots"].url == "https://peter-tanner.com/moneypuck/downloads/shots_2026.zip"


def test_only_the_regular_skater_goalie_and_shot_files_are_required():
    required = {s.name for s in current_asset_specs(2026) if s.required}
    assert required == {"skaters_regular", "goalies_regular", "shots"}


def test_probe_issues_head_requests_only_for_those_files():
    http = FakeHTTP()
    probe_sources(2026, client=http)
    assert len(http.requested) == 7
    assert all("api-web.nhle.com" not in url and "api.nhle.com" not in url for url in http.requested)


def test_no_playoff_files_yet_is_still_ready():
    result = probe(missing=("playoffs",))
    assert result.ready
    assert result.error_code is None
    playoffs = [a for a in result.assets if a.name.endswith("playoffs")]
    assert playoffs and all(a.status_code == 404 and not a.available for a in playoffs)


def test_missing_teams_file_does_not_block_the_core_feed():
    assert probe(missing=("teams.csv",)).ready


def test_a_missing_required_file_is_reported_as_pending():
    result = probe(missing=("shots_2026.zip",))
    assert not result.ready
    assert result.error_code == "http_404"


def test_source_published_at_is_the_newest_last_modified_in_utc():
    assert probe().source_published_at == "2026-10-08T10:31:15+00:00"


def test_http_dates_parse_to_utc_and_junk_does_not():
    assert parse_source_timestamp("Thu, 08 Oct 2026 10:31:15 GMT") == datetime(
        2026, 10, 8, 10, 31, 15, tzinfo=timezone.utc
    )
    assert parse_source_timestamp("not a date") is None
    assert parse_source_timestamp(None) is None


def test_fingerprint_ignores_probe_time_and_tracks_file_generation():
    assert probe(tag="one").fingerprint == probe(tag="one").fingerprint
    assert probe(tag="one").fingerprint != probe(tag="two").fingerprint


def test_a_playoff_file_appearing_starts_a_new_generation():
    assert probe(missing=("playoffs",)).fingerprint != probe().fingerprint


def test_fingerprint_is_order_independent():
    base = [
        AssetProbe("a", "u", True, 200, '"1"', "lm", "10"),
        AssetProbe("b", "v", False, 200, '"2"', "lm", "20"),
    ]
    assert fingerprint_assets(base) == fingerprint_assets(list(reversed(base)))


def test_probe_asset_keeps_status_when_head_is_unavailable():
    asset = probe_asset(FakeHTTP(missing=("shots_2026.zip",)), AssetSpec("shots", "https://x/shots_2026.zip", True))
    assert asset.status_code == 404 and not asset.available
    assert asset.error_code == "http_404"


def test_a_network_error_is_recorded_not_raised():
    class Down:
        def head(self, url, *, timeout):
            raise TimeoutError("timed out")

    asset = probe_asset(Down(), AssetSpec("shots", "https://x", True))
    assert asset.status_code is None
    assert asset.error_code == "network_error"
