#!/usr/bin/env python3
"""Static safety contracts for the destructive deployed-demo reset."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "bin" / "foaf-reset-demo").read_text()


class FoafResetDemoSafetyTest(unittest.TestCase):
    def test_demo_database_allowlist_precedes_destructive_sql(self) -> None:
        allowlist = 'if [[ "${APP_DB_NAME}" != "${EXPECTED_APP_DB}" ]]'
        destructive_sql = "DROP TABLE IF EXISTS"

        self.assertIn('EXPECTED_APP_DB="growoperative_demo"', SCRIPT)
        self.assertLess(SCRIPT.index(allowlist), SCRIPT.index(destructive_sql))

    def test_reset_drops_all_existing_base_tables_before_snapshot_import(self) -> None:
        discover_tables = "FROM information_schema.tables"
        execute_drop = "EXECUTE drop_demo_tables"
        import_snapshot = '< "${APP_SNAPSHOT_PATH}"'

        self.assertIn("SET FOREIGN_KEY_CHECKS=0", SCRIPT)
        self.assertIn("TABLE_TYPE = 'BASE TABLE'", SCRIPT)
        self.assertLess(SCRIPT.index(discover_tables), SCRIPT.index(execute_drop))
        self.assertLess(SCRIPT.index(execute_drop), SCRIPT.index(import_snapshot))

    def test_foaf_testnet_guard_precedes_destructive_sql(self) -> None:
        network_guard = 'if [[ "${FOAF_NETWORK_ACTUAL}" != "${EXPECTED_FOAF_NETWORK}" ]]'

        self.assertIn('EXPECTED_FOAF_NETWORK="testnet"', SCRIPT)
        self.assertLess(SCRIPT.index(network_guard), SCRIPT.index("DROP TABLE IF EXISTS"))


if __name__ == "__main__":
    unittest.main()
