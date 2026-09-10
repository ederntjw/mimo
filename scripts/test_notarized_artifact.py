#!/usr/bin/env python3
"""Behavioral notarization gates; all Apple tools use isolated temporary stubs."""
import base64
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "scripts/verify_notarized_artifact.sh"
VERIFIER = ROOT / "scripts/verify_update_flow.sh"
FEED_URL = "https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml"


class NotarizedArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mimo-notary-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.app = self.root / "Mimo test.app"
        self.app.mkdir()
        self.dmg = self.root / "Mimo test.dmg"
        self.dmg.write_bytes(b"fixture disk image; not a real artifact")
        self.calls = self.root / "calls"
        self.calls.mkdir()
        for name, body in {
            "spctl": '''#!/bin/bash
printf '%s\\0' "$@" > "$TEST_TOOL_CALLS/spctl"
printf '%s\\n' "$TEST_ASSESSMENT_OUTPUT" >&2
exit "${TEST_ASSESSMENT_EXIT:-0}"
''',
            "syspolicy_check": '''#!/bin/bash
printf '%s\\0' "$@" > "$TEST_TOOL_CALLS/syspolicy_check"
if [[ "$1" != distribution ]]; then exit 97; fi
exit "${TEST_DISTRIBUTION_EXIT:-0}"
''',
            "xcrun": '''#!/bin/bash
printf '%s\\0' "$@" > "$TEST_TOOL_CALLS/xcrun"
if [[ "$1" != stapler || "$2" != validate ]]; then exit 97; fi
exit "${TEST_STAPLER_EXIT:-0}"
''',
        }.items():
            tool = self.bin / name
            tool.write_text(body, encoding="utf-8")
            tool.chmod(0o755)

    def run_gate(self, artifact=None, mode="--app", output=None, assessment_exit=0, staple_exit=0, distribution_exit=0, restricted_path=False):
        artifact = artifact or self.app
        if output is None:
            output = f"{artifact}: accepted\nsource=Notarized Developer ID\norigin=Developer ID Application: Fixture (TESTTEAM)"
        environment = os.environ.copy()
        environment.update({
            "PATH": str(self.bin) if restricted_path else str(self.bin) + os.pathsep + os.environ.get("PATH", ""),
            "TEST_TOOL_CALLS": str(self.calls),
            "TEST_ASSESSMENT_OUTPUT": output,
            "TEST_ASSESSMENT_EXIT": str(assessment_exit),
            "TEST_STAPLER_EXIT": str(staple_exit),
            "TEST_DISTRIBUTION_EXIT": str(distribution_exit),
        })
        return subprocess.run(
            [str(HELPER), mode, str(artifact)], env=environment,
            capture_output=True, text=True, check=False,
        )

    def arguments_for(self, tool):
        return (self.calls / tool).read_bytes().decode().rstrip("\0").split("\0")

    def test_notarized_developer_id_app_with_ticket_passes(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments_for("xcrun"), ["stapler", "validate", str(self.app)])
        self.assertIn("execute", self.arguments_for("spctl"))
        self.assertEqual(self.arguments_for("syspolicy_check"), ["distribution", str(self.app)])

    def test_notarized_dmg_uses_primary_signature_assessment(self):
        result = self.run_gate(artifact=self.dmg, mode="--dmg")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments_for("xcrun"), ["stapler", "validate", str(self.dmg)])
        self.assertIn("open", self.arguments_for("spctl"))
        self.assertIn("context:primary-signature", self.arguments_for("spctl"))
        self.assertFalse((self.calls / "syspolicy_check").exists())

    def test_nonzero_assessment_fails_even_if_output_says_accepted(self):
        result = self.run_gate(assessment_exit=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_not_accepted_substring_is_not_acceptance(self):
        result = self.run_gate(output=f"{self.app}: not accepted\nsource=Notarized Developer ID")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_acceptance_for_another_artifact_does_not_pass(self):
        result = self.run_gate(output="/tmp/unrelated.app: accepted\nsource=Notarized Developer ID")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_local_override_without_notarization_does_not_pass(self):
        result = self.run_gate(output=f"{self.app}: accepted\nsource=Local Override")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_unsigned_preview_does_not_pass(self):
        result = self.run_gate(
            output=f"{self.app}: rejected\nsource=no usable signature", assessment_exit=3,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_distribution_assessment_failure_does_not_pass(self):
        result = self.run_gate(distribution_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.arguments_for("syspolicy_check"), ["distribution", str(self.app)])
        self.assertFalse((self.calls / "xcrun").exists())

    def test_missing_distribution_tool_fails_without_invoking_real_system_tool(self):
        (self.bin / "syspolicy_check").unlink()
        # A closed PATH makes this test independent of the host macOS version
        # and guarantees it cannot fall through to the user's system assessor.
        for name in ("bash", "dirname", "basename", "grep"):
            executable = shutil.which(name)
            self.assertIsNotNone(executable)
            (self.bin / name).symlink_to(executable)
        result = self.run_gate(restricted_path=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("syspolicy_check is required", result.stderr)
        self.assertFalse((self.calls / "xcrun").exists())

    def test_symlinked_parent_is_assessed_using_the_same_physical_path(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        result = self.run_gate(
            artifact=alias / self.app.name,
            output=f"{self.app}: accepted\nsource=Notarized Developer ID",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments_for("spctl")[-1], str(self.app))
        self.assertEqual(self.arguments_for("syspolicy_check")[-1], str(self.app))
        self.assertEqual(self.arguments_for("xcrun")[-1], str(self.app))

    def test_missing_ticket_does_not_pass_after_gatekeeper_acceptance(self):
        result = self.run_gate(staple_exit=65)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.calls / "xcrun").exists())

    def test_missing_artifact_never_calls_system_tools(self):
        result = self.run_gate(artifact=self.root / "missing.app")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.calls / "spctl").exists())
        self.assertFalse((self.calls / "xcrun").exists())

    def test_requiring_notarization_cannot_be_bypassed_with_skip_dmg(self):
        signature = base64.b64encode(bytes(64)).decode("ascii")
        appcast = self.root / "appcast.xml"
        appcast.write_text(f'''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><item><title>0.8.5</title><description>Fixture notes</description>
<sparkle:version>0.8.5</sparkle:version><sparkle:shortVersionString>0.8.5</sparkle:shortVersionString>
<enclosure url="https://github.com/ederntjw/mimo/releases/download/v0.8.5/Mimo-0.8.5.dmg" length="42" sparkle:edSignature="{signature}"/>
</item></channel></rss>''', encoding="utf-8")
        command = [
            str(VERIFIER), "--version", "0.8.5", "--appcast", str(appcast),
            "--app-name", "Mimo", "--feed-url", FEED_URL,
            "--github-repository", "ederntjw/mimo", "--skip-dmg",
        ]
        metadata_only = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(metadata_only.returncode, 0, metadata_only.stderr)
        required = subprocess.run(command + ["--require-notarized"], capture_output=True, text=True, check=False)
        self.assertNotEqual(required.returncode, 0, "Required notarization was silently skipped")
        self.assertIn("--skip-dmg", required.stderr)
        self.assertIn("--require-notarized", required.stderr)


if __name__ == "__main__":
    unittest.main()
