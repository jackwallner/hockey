import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch


with patch.dict(os.environ, {
    "SUPABASE_URL": "https://example.invalid",
    "SUPABASE_ANON_KEY": "test-only",
    "STATCAST_SEASON": "2026",
}):
    spec = importlib.util.spec_from_file_location(
        "export_historical", Path(__file__).parents[1] / "export_historical.py"
    )
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)

CATEGORY_BY_TYPE = {"f": "Scoring", "d": "Play Driving", "g": "Goaltending"}


class ExportCoverageTests(unittest.TestCase):
    def rows(self, season: int, teams: int = 2) -> list[dict]:
        """Synthetic REG rows: ``teams`` clubs, all three cohorts."""
        out = []
        for index in range(max(30, teams)):
            player_type = ["f", "d", "g"][index % 3]
            out.append({
                "id": index, "season": season, "season_type": "REG",
                "team": f"T{index % teams:02d}",
                "player_type": player_type,
                "metrics": [
                    {"label": "xGF%", "category": CATEGORY_BY_TYPE[player_type]},
                    {"label": "ixG", "category": "Shot Quality"},
                    {"label": "GSAx", "category": "Goaltending"},
                ],
            })
        return out

    def test_opening_night_can_ship_as_current_fallback(self) -> None:
        exporter.validate_export(self.rows(2026), {2026}, require_rate_metrics=True)

    def test_two_team_historical_season_is_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Incomplete 2025"):
            exporter.validate_export(self.rows(2025), {2025}, require_rate_metrics=False)

    def test_full_league_historical_season_ships(self) -> None:
        exporter.validate_export(self.rows(2025, teams=32), {2025}, require_rate_metrics=False)

    def test_team_floor_follows_league_size(self) -> None:
        self.assertEqual(exporter.minimum_teams(2008), 30)
        self.assertEqual(exporter.minimum_teams(2017), 31)
        self.assertEqual(exporter.minimum_teams(2021), 32)
        exporter.validate_export(self.rows(2010, teams=30), {2010}, require_rate_metrics=False)
        with self.assertRaisesRegex(RuntimeError, "Incomplete 2018"):
            exporter.validate_export(self.rows(2018, teams=30), {2018}, require_rate_metrics=False)

    def test_one_sided_current_game_is_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Incomplete current season"):
            exporter.validate_export(self.rows(2026, teams=1), {2026}, require_rate_metrics=True)

    def test_missing_goalies_are_rejected(self) -> None:
        rows = [row for row in self.rows(2026) if row["player_type"] != "g"]
        with self.assertRaisesRegex(RuntimeError, "Incomplete current season"):
            exporter.validate_export(rows, {2026}, require_rate_metrics=True)

    def test_unknown_metric_category_is_rejected(self) -> None:
        rows = self.rows(2026)
        rows[0]["metrics"][0]["category"] = "Passing"
        with self.assertRaisesRegex(RuntimeError, "Unexpected metric categories"):
            exporter.validate_export(rows, {2026}, require_rate_metrics=True)

    def test_duplicate_player_phase_cannot_ship(self) -> None:
        rows = self.rows(2026)
        with self.assertRaisesRegex(RuntimeError, "Duplicate"):
            exporter.validate_export(rows + [rows[0]], {2026}, require_rate_metrics=True)

    def test_career_rollup_is_checked_on_size_and_cohorts(self) -> None:
        rows = [dict(row, season=0) for row in self.rows(0)]
        with self.assertRaisesRegex(RuntimeError, "Incomplete career rollup"):
            exporter.validate_export(rows, {0}, require_rate_metrics=False)
        many = [dict(row, id=index) for index, row in enumerate(rows * 4)]
        exporter.validate_export(many, {0}, require_rate_metrics=False)

    def test_historical_range_starts_at_moneypucks_floor(self) -> None:
        self.assertEqual(exporter.OLDEST_SUPPORTED_SEASON, 2008)
        self.assertEqual(exporter.REQUIRED_TYPES, {"f", "d", "g"})


if __name__ == "__main__":
    unittest.main()
