#!/usr/bin/env python3

import os
import subprocess
import unittest
from unittest.mock import patch

import trade_test


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self.payload


def reconcile(app_balance, foaf_balance):
    return {
        "summary": {"matches": 0},
        "trustlines": [{
            "user_a": "alice",
            "user_b": "bob",
            "app": {"balance": app_balance},
            "foaf": {"balance": foaf_balance},
        }],
    }


class CredloopAssertionTest(unittest.TestCase):
    @patch.object(trade_test.time, "sleep")
    @patch.object(trade_test.requests, "get")
    def test_retries_until_a_credloop_cancellation_is_visible(self, get, _sleep):
        get.side_effect = [
            FakeResponse(reconcile(10, 10)),
            FakeResponse(reconcile(10, 4)),
        ]

        count = trade_test.check_credloop_fired(attempts=2, interval=0)

        self.assertEqual(1, count)
        self.assertEqual(2, get.call_count)

    @patch.object(trade_test.time, "sleep")
    @patch.object(trade_test.requests, "get")
    def test_missing_credloop_cancellation_is_fatal(self, get, _sleep):
        get.return_value = FakeResponse(reconcile(10, 10))

        with self.assertRaisesRegex(trade_test.SetupError, "Expected at least 1"):
            trade_test.check_credloop_fired(attempts=2, interval=0)


class WrapperResetRoutingTest(unittest.TestCase):
    script = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "bin", "foaf-trade-test"))

    def bash_function(self, body):
        return subprocess.run(
            ["bash", "-c", f"source \"$1\"; {body}", "bash", self.script],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_demo_hosts_use_only_the_deployed_demo_reset(self):
        for host in ("https://demo.growoperative.app", "https://dpi.growoperative.app/"):
            result = self.bash_function(
                f'mode="$(select_reset_mode "{host}")"; reset_command_for_mode "$mode"'
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("./bin/foaf-reset-demo", result.stdout.strip())

    def test_local_hosts_use_only_the_local_reset(self):
        result = self.bash_function(
            'mode="$(select_reset_mode "http://localhost:3001")"; reset_command_for_mode "$mode"'
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("./bin/foaf-reset", result.stdout.strip())

    def test_unknown_host_is_refused_before_any_reset_command_is_selected(self):
        result = self.bash_function('select_reset_mode "https://api.growoperative.app"')
        self.assertEqual(2, result.returncode)
        self.assertIn("REFUSED", result.stderr)


if __name__ == "__main__":
    unittest.main()
