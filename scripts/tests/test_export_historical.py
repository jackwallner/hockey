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


class ExportCoverageTests(unittest.TestCase):
    def rows(self, season: int) -> list[dict]:
        return [
            {
                "id": index, "season": season, "season_type": "REG",
                "team": "SEA" if index < 10 else "NE",
                "player_type": ["qb", "rb", "wr", "te", "def"][index % 5],
                "metrics": [{"label": "EPA/Play"}, {"label": "EPA/Rush"}, {"label": "EPA/Tgt"}],
            }
            for index in range(20)
        ]

    def test_opening_game_can_ship_as_current_fallback(self) -> None:
        exporter.validate_export(self.rows(2026), {2026}, require_rate_metrics=True)

    def test_two_team_historical_season_is_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Incomplete 2025"):
            exporter.validate_export(self.rows(2025), {2025}, require_rate_metrics=False)

    def test_one_sided_current_game_is_rejected(self) -> None:
        rows = self.rows(2026)
        for row in rows:
            row["team"] = "SEA"
        with self.assertRaisesRegex(RuntimeError, "Incomplete current season"):
            exporter.validate_export(rows, {2026}, require_rate_metrics=True)

    def test_duplicate_player_phase_cannot_ship(self) -> None:
        rows = self.rows(2026)
        with self.assertRaisesRegex(RuntimeError, "Duplicate"):
            exporter.validate_export(rows + [rows[0]], {2026}, require_rate_metrics=True)


if __name__ == "__main__":
    unittest.main()
