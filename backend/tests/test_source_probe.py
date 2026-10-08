from datetime import datetime, timezone

from source_probe import (
    AssetSpec,
    AssetProbe,
    fingerprint_assets,
    parse_source_timestamp,
    probe_asset,
    probe_sources,
)


class Response:
    def __init__(self, status_code, payload=b"", headers=None):
        self.status_code = status_code
        self._payload = payload
        self.headers = headers or {}

    def read(self):
        return self._payload


class FakeHTTP:
    def __init__(
        self,
        *,
        timestamp=b'{"last_updated":"2026-09-12 08:52:24 EDT"}',
        head=None,
        missing_optional=False,
    ):
        self.timestamp = timestamp
        self.missing_optional = missing_optional
        self.head_response = head or Response(
            200,
            headers={
                "ETag": '"generation-1"',
                "Last-Modified": "Sat, 12 Sep 2026 12:52:18 GMT",
                "Content-Length": "71654",
            },
        )

    def get(self, url, *, timeout):
        return Response(200, self.timestamp)

    def head(self, url, *, timeout):
        if self.missing_optional and "pfr_advstats" in url:
            return Response(404, headers={})
        return self.head_response


def test_nflverse_timestamp_is_normalized_to_utc():
    assert parse_source_timestamp("2026-09-12 08:52:24 EDT") == datetime(
        2026, 9, 12, 12, 52, 24, tzinfo=timezone.utc
    )


def test_fingerprint_ignores_probe_time_and_tracks_asset_generation():
    base = AssetProbe(
        "stats_player_week", "stats_player", "stats_player_week_2026.parquet", True,
        "timestamp", "asset", 200, "2026-09-12 08:52:24 EDT", '"one"', "date", "10",
    )
    same = AssetProbe(**{**base.__dict__})
    changed = AssetProbe(**{**base.__dict__, "etag": '"two"'})
    assert fingerprint_assets([base]) == fingerprint_assets([same])
    assert fingerprint_assets([base]) != fingerprint_assets([changed])


def test_schedule_republish_does_not_start_a_new_generation():
    stats = AssetProbe(
        "stats_player_week", "stats_player", "stats_player_week_2026.parquet", True,
        "timestamp", "asset", 200, "2026-09-12 08:52:24 EDT", '"one"', "date", "10",
    )
    schedule = AssetProbe(
        "schedule", "schedules", "games.parquet", True,
        "timestamp", "asset", 200, "2026-09-12 17:36:26 EDT", '"a"', "date", "20",
    )
    republished = AssetProbe(**{**schedule.__dict__, "etag": '"b"', "timestamp": "2026-09-12 18:06:16 EDT"})
    assert fingerprint_assets([stats, schedule]) == fingerprint_assets([stats, republished])


def test_optional_asset_failure_does_not_block_core_probe():
    result = probe_sources(2018, client=FakeHTTP(missing_optional=True))
    assert result.ready
    assert result.source_published_at == "2026-09-12T12:52:24+00:00"
    assert {asset.name for asset in result.assets} >= {
        "stats_player_week", "schedule", "ngs_passing", "pfr_advstats_def",
    }


def test_required_asset_failure_is_reported_as_pending():
    result = probe_sources(
        2026,
        client=FakeHTTP(head=Response(404, headers={})),
    )
    assert not result.ready
    assert result.error_code == "http_404"


def test_probe_asset_keeps_timestamp_when_asset_head_is_unavailable():
    asset = probe_asset(
        FakeHTTP(head=Response(503, headers={})),
        AssetSpec("stats", "stats_player", "stats_player_week_2026.parquet", True),
    )
    assert asset.timestamp == "2026-09-12 08:52:24 EDT"
    assert not asset.available
    assert asset.error_code == "http_503"
