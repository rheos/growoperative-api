#!/usr/bin/env python3
"""Static safety contracts for the destructive deployed-demo reset."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "bin" / "foaf-reset-demo").read_text()
LOCAL_SCRIPT = (ROOT / "bin" / "foaf-reset").read_text()
WAIT_SCRIPT = (ROOT / "bin" / "wait-for-db.sh").read_text()


class FoafResetDemoSafetyTest(unittest.TestCase):
    def test_demo_database_allowlist_precedes_destructive_sql(self) -> None:
        allowlist = 'if [[ "${APP_DB_NAME}" != "${EXPECTED_APP_DB}" ]]'
        destructive_sql = "DROP SCHEMA public CASCADE"

        self.assertIn('EXPECTED_APP_DB="growoperative_demo"', SCRIPT)
        self.assertLess(SCRIPT.index(allowlist), SCRIPT.index(destructive_sql))

    def test_reset_drops_all_existing_base_tables_before_snapshot_import(self) -> None:
        drop_schema = "DROP SCHEMA public CASCADE"
        import_snapshot = 'restore_snapshot_to_url "${BACKEND_CONTAINER}" "${APP_DATABASE_URL}" "${APP_SNAPSHOT_PATH}"'

        self.assertIn("restore_snapshot_to_url", SCRIPT)
        self.assertLess(SCRIPT.index(drop_schema), SCRIPT.index(import_snapshot))

    def test_foaf_testnet_guard_precedes_destructive_sql(self) -> None:
        network_guard = 'if [[ "${FOAF_NETWORK_ACTUAL}" != "${EXPECTED_FOAF_NETWORK}" ]]'

        self.assertIn('EXPECTED_FOAF_NETWORK="testnet"', SCRIPT)
        self.assertLess(SCRIPT.index(network_guard), SCRIPT.index("DROP SCHEMA public CASCADE"))

    def test_demo_script_uses_postgres_restore_tooling(self) -> None:
        self.assertNotIn("mysql", SCRIPT)
        self.assertNotIn("FOREIGN_KEY_CHECKS", SCRIPT)
        self.assertIn('DATABASE_URL', SCRIPT)
        self.assertIn('sh -lc \'exec psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"\'', SCRIPT)
        self.assertIn('pg_restore --clean --if-exists --no-owner --no-privileges', SCRIPT)
        self.assertIn('PostgreSQL database dump', SCRIPT)
        self.assertIn("use .sql or .sql.gz here", SCRIPT)


class FoafResetLocalSafetyTest(unittest.TestCase):
    def test_local_script_uses_postgres_restore_tooling(self) -> None:
        self.assertNotIn("mysql", LOCAL_SCRIPT)
        self.assertNotIn("FOREIGN_KEY_CHECKS", LOCAL_SCRIPT)
        self.assertIn('docker_exec_compose exec -T backend printenv DATABASE_URL', LOCAL_SCRIPT)
        self.assertIn('DROP SCHEMA public CASCADE; CREATE SCHEMA public;', LOCAL_SCRIPT)
        self.assertIn('TRUNCATE TABLE', LOCAL_SCRIPT)
        self.assertIn('PostgreSQL database dump', LOCAL_SCRIPT)

    def test_local_script_requires_postgres_snapshots(self) -> None:
        self.assertIn("MySQL-era snapshots are not supported", LOCAL_SCRIPT)
        self.assertIn("dev_clean_${SNAPSHOT_DATE}.{sql,sql.gz,dump,backup,tar}", LOCAL_SCRIPT)


class WaitForDbContractTest(unittest.TestCase):
    def test_wait_script_uses_pg_isready_not_mysql(self) -> None:
        self.assertIn("pg_isready", WAIT_SCRIPT)
        self.assertNotIn("mysql --skip-ssl", WAIT_SCRIPT)
        self.assertIn('wait_target=(-d "${DATABASE_URL}")', WAIT_SCRIPT)
        self.assertIn('PostgreSQL is up', WAIT_SCRIPT)


if __name__ == "__main__":
    unittest.main()
