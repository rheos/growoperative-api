#!/usr/bin/env python3
"""Regression checks for production/demo deployment isolation."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DeployIsolationTest(unittest.TestCase):
    def workflow(self, name: str) -> str:
        return (ROOT / ".github" / "workflows" / name).read_text()

    def test_demo_recreates_only_demo_backend(self) -> None:
        workflow = self.workflow("deploy-demo.yml")

        self.assertIn(
            "up -d --force-recreate --no-deps backend-demo",
            workflow,
        )
        self.assertNotIn("force-recreate nginx", workflow)
        self.assertIn("exec -T nginx nginx -s reload", workflow)

    def test_production_recreates_only_production_backend(self) -> None:
        workflow = self.workflow("deploy-prod.yml")

        self.assertIn(
            "up -d --force-recreate --no-deps backend",
            workflow,
        )
        self.assertNotIn("force-recreate nginx", workflow)
        self.assertIn("exec -T nginx nginx -s reload", workflow)


if __name__ == "__main__":
    unittest.main()
