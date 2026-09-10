#!/usr/bin/env python3
"""Exercise installer signing policy with fake metadata and no Keychain access."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
IDENTITY = "Developer ID Application: Mimo Test (TESTTEAM01)"
ROTATED_IDENTITY = "Developer ID Application: Mimo New Name (TESTTEAM01)"


class LocalAppSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mimo-signing-policy-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.installed = self.directory / "Installed.app"
        self.installed.mkdir()
        self.staged = self.directory / "Staged.app"
        self.staged.mkdir()
        self.security_log = self.directory / "security-calls"
        # Only these ordinary text tools are available. Apple signing commands
        # are always stubs, including when the tests run on a real macOS host.
        for name in ("sed", "head", "grep"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.write_tool("codesign", """#!/bin/bash
[[ "$1" == -dvvv ]] || exit 90
[[ "${FAKE_INSPECTION_FAILURE:-0}" != 1 ]] || exit 1
case "$2" in
  "$FAKE_INSTALLED_PATH") authority="$FAKE_INSTALLED_AUTHORITY" ;;
  "$FAKE_STAGED_PATH") authority="$FAKE_STAGED_AUTHORITY" ;;
  *) exit 91 ;;
esac
if [[ -n "$authority" ]]; then
  printf 'Authority=%s\nAuthority=Developer ID Certification Authority\n' "$authority"
else
  printf 'Signature=adhoc\n'
fi
""")
        self.write_tool("security", """#!/bin/bash
[[ "$*" == 'find-identity -v -p codesigning' ]] || exit 92
printf 'called\n' >> "$FAKE_SECURITY_LOG"
[[ "${FAKE_SECURITY_FAILURE:-0}" != 1 ]] || exit 1
printf '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "%s"\n' "$FAKE_AVAILABLE_IDENTITY"
""")

    def write_tool(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def run_policy(self, *, installed=IDENTITY, requested="", available=IDENTITY,
                   staged=IDENTITY, needs_build=True, inspect_failure=False,
                   security_failure=False):
        env = os.environ.copy()
        env.update({
            "PATH": str(self.bin),
            "FAKE_INSTALLED_PATH": str(self.installed),
            "FAKE_STAGED_PATH": str(self.staged),
            "FAKE_INSTALLED_AUTHORITY": installed,
            "FAKE_STAGED_AUTHORITY": staged,
            "FAKE_AVAILABLE_IDENTITY": available,
            "FAKE_INSPECTION_FAILURE": str(int(inspect_failure)),
            "FAKE_SECURITY_FAILURE": str(int(security_failure)),
            "FAKE_SECURITY_LOG": str(self.security_log),
        })
        return subprocess.run([
            "/bin/bash", "-c", """set -euo pipefail
source "$1"
mimo_resolve_local_app_signing "$2" "$3" "$4"
mimo_verify_local_app_signer "$5"
printf 'identity=%s\ntimestamp=%s\n' "$LOCAL_SIGN_IDENTITY" "$LOCAL_SIGN_TIMESTAMP"
""", "policy-test", str(ROOT / "scripts/local_app_signing.sh"),
            str(self.installed), requested, str(int(needs_build)), str(self.staged),
        ], env=env, text=True, capture_output=True, timeout=10)

    def test_build_preserves_installed_developer_id_and_timestamp(self):
        result = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"identity={IDENTITY}\ntimestamp=--timestamp", result.stdout)
        self.assertEqual(self.security_log.read_text(), "called\n")

    def test_missing_build_identity_fails_instead_of_falling_back(self):
        result = self.run_policy(available="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity is unavailable", result.stderr)

    def test_keychain_failure_fails_instead_of_falling_back(self):
        result = self.run_policy(security_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity is unavailable", result.stderr)

    def test_local_adhoc_install_can_be_upgraded_to_developer_id(self):
        result = self.run_policy(installed="", needs_build=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.security_log.exists())

    def test_initial_local_build_can_still_use_adhoc(self):
        result = self.run_policy(installed="", staged="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("identity=-\ntimestamp=none", result.stdout)
        self.assertFalse(self.security_log.exists())

    def test_explicit_adhoc_cannot_downgrade_developer_id(self):
        for needs_build in (True, False):
            with self.subTest(needs_build=needs_build):
                result = self.run_policy(requested="-", staged="", needs_build=needs_build)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ad-hoc signing", result.stderr)
        self.assertFalse(self.security_log.exists())

    def test_staged_app_preserves_identity_without_requiring_private_key(self):
        result = self.run_policy(needs_build=False, available="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.security_log.exists())

    def test_staged_adhoc_or_other_identity_is_rejected(self):
        for staged in ("", ROTATED_IDENTITY):
            with self.subTest(staged=staged):
                result = self.run_policy(staged=staged, needs_build=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("does not preserve", result.stderr)

    def test_explicit_developer_id_migration_is_allowed(self):
        result = self.run_policy(requested=ROTATED_IDENTITY,
                                 available=ROTATED_IDENTITY, staged=ROTATED_IDENTITY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"identity={ROTATED_IDENTITY}", result.stdout)

    def test_apple_development_identity_is_rejected(self):
        result = self.run_policy(requested="Apple Development: Mimo Test (TESTTEAM01)")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must name a Developer ID Application", result.stderr)
        self.assertFalse(self.security_log.exists())

    def test_signature_inspection_failure_cannot_silently_downgrade(self):
        result = self.run_policy(inspect_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot inspect", result.stderr)
        self.assertFalse(self.security_log.exists())


if __name__ == "__main__":
    unittest.main()
