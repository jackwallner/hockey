from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "asc_lib", Path(__file__).parents[1] / "asc_lib.py"
)
asc_lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc_lib)


class DraftVersionTests(unittest.TestCase):
    def test_existing_live_preferred_version_is_used_as_bump_base(self) -> None:
        live = {
            "id": "live-version",
            "attributes": {
                "versionString": "1.2.1",
                "appStoreState": "READY_FOR_SALE",
            },
        }
        draft = {
            "id": "draft-version",
            "attributes": {"versionString": "1.2.2"},
        }
        client = Mock()

        def existing_version(_client: object, _app_id: str, version: str) -> dict | None:
            return live if version == "1.2.1" else None

        with (
            patch.object(asc_lib, "find_editable_version", return_value=None),
            patch.object(asc_lib, "find_live_version", return_value=live),
            patch.object(asc_lib, "find_version_by_string", side_effect=existing_version),
            patch.object(asc_lib, "create_draft_version", return_value=draft) as create,
        ):
            result = asc_lib.ensure_draft_version(client, "app-id", "1.2.1")

        create.assert_called_once_with(client, "app-id", "1.2.2")
        self.assertEqual(result["id"], "draft-version")

    def test_existing_editable_version_is_reused(self) -> None:
        draft = {
            "id": "draft-version",
            "attributes": {
                "versionString": "1.2.2",
                "appStoreState": "PREPARE_FOR_SUBMISSION",
            },
        }
        client = Mock()

        with (
            patch.object(asc_lib, "find_editable_version", return_value=draft),
            patch.object(asc_lib, "create_draft_version") as create,
        ):
            result = asc_lib.ensure_draft_version(client, "app-id", "1.2.1")

        create.assert_not_called()
        self.assertEqual(result["id"], "draft-version")


if __name__ == "__main__":
    unittest.main()
