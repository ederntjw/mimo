#!/usr/bin/env python3
import os
import subprocess
import sys
import unittest
from pathlib import Path

from validate_mimo_sync_configuration import validate_sync_configuration


class MimoSyncConfigurationTests(unittest.TestCase):
    def test_absent_configuration_supports_a_local_library(self) -> None:
        self.assertFalse(validate_sync_configuration("", ""))
        self.assertFalse(validate_sync_configuration(" \n", "\t "))

    def test_both_values_enable_sync_with_https_and_custom_domains(self) -> None:
        for project_url in ("https://example.supabase.co", "https://sync.example.com/", " https://sync.example.com "):
            with self.subTest(project_url=project_url):
                self.assertTrue(validate_sync_configuration(project_url, " publishable-client-key "))

    def test_partial_configuration_fails(self) -> None:
        for project_url, key in (("https://example.supabase.co", ""), ("", "client-key"), (" ", "client-key")):
            with self.subTest(project_url=project_url, key=key):
                with self.assertRaisesRegex(ValueError, "Set both"):
                    validate_sync_configuration(project_url, key)

    def test_invalid_project_urls_fail_without_exposing_values(self) -> None:
        for project_url in (
            "http://example.supabase.co", "ftp://example.supabase.co", "example.supabase.co",
            "https:///missing-host", "https://", "https://bad host.example", "https://[broken",
            "https://example.com:99999", "https://example.com:not-a-port",
            "https://secret@example.com", "https://example.com?token=secret", "https://example.com#secret",
        ):
            with self.subTest(project_url=project_url):
                with self.assertRaisesRegex(ValueError, "HTTPS project URL") as raised:
                    validate_sync_configuration(project_url, "private-looking-test-value")
                self.assertNotIn(project_url, str(raised.exception))
                self.assertNotIn("private-looking-test-value", str(raised.exception))

    def test_cli_allows_absent_pair_and_rejects_partial_pair(self) -> None:
        environment = dict(os.environ)
        environment.pop("MIMO_SUPABASE_URL", None)
        environment.pop("MIMO_SUPABASE_PUBLISHABLE_KEY", None)
        script = Path(__file__).with_name("validate_mimo_sync_configuration.py")
        result = subprocess.run([sys.executable, str(script)], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("library stays on this Mac", result.stdout)
        environment["MIMO_SUPABASE_PUBLISHABLE_KEY"] = "private-looking-test-value"
        result = subprocess.run([sys.executable, str(script)], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Set both", result.stderr)
        self.assertNotIn("private-looking-test-value", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
