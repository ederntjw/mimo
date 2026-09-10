#!/usr/bin/env python3
"""Execute release workflow keychain steps with a closed PATH of harmless stubs."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/mimo-release.yml"


def workflow_run_step(name):
    marker = f"      - name: {name}\n"
    workflow = WORKFLOW.read_text(encoding="utf-8")
    section = workflow.split(marker, 1)[1].split("\n      - name:", 1)[0]
    return textwrap.dedent(section.split("        run: |\n", 1)[1])


class ReleaseKeychainTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mimo-signing-step-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.runner = self.root / "runner temp"
        self.runner.mkdir()
        self.originals = [str(self.root / "original login.keychain-db"), str(self.root / "another.keychain-db")]
        for path in self.originals:
            Path(path).write_bytes(b"original fixture keychain")
        self.original_default = self.originals[0]
        self.state_path = self.root / "state.json"
        self.write_state({"search": self.originals, "default": self.original_default, "calls": []})
        self.environment_file = self.root / "github-env"
        self.environment_file.touch()
        self.environment = {
            "PATH": str(self.bin),
            "RUNNER_TEMP": str(self.runner),
            "GITHUB_ENV": str(self.environment_file),
            "MIMO_DEVELOPER_ID_CERTIFICATE_BASE64": "Zml4dHVyZQ==",
            "MIMO_DEVELOPER_ID_CERTIFICATE_PASSWORD": "fixture-password",
            "MIMO_NOTARY_APPLE_ID": "fixture@example.invalid",
            "MIMO_NOTARY_APP_PASSWORD": "fixture-notary-password",
            "MIMO_NOTARY_TEAM_ID": "FIXTURETEAM",
            "TEST_SIGNING_STATE": str(self.state_path),
            "TEST_SIGNING_ROOT": str(self.root),
        }
        # Closed PATH prevents any accidental fallthrough to security/xcrun on
        # the host; Python and rm are used only with temporary fixture paths.
        for name, executable in {"python3": sys.executable, "rm": shutil.which("rm")}.items():
            self.assertIsNotNone(executable)
            (self.bin / name).symlink_to(executable)
        self.install_stub("openssl", 'print("fixture-random-keychain-password")')
        self.install_stub("base64", 'import sys; sys.stdout.buffer.write(b"fixture certificate bytes")')
        self.install_stub("xcrun", '''
import os, sys
raise SystemExit(int(os.environ.get("TEST_NOTARY_EXIT", "0")))
''')
        self.install_stub("security", '''
import json, os, pathlib, sys
path = pathlib.Path(os.environ["TEST_SIGNING_STATE"])
state = json.loads(path.read_text())
args = sys.argv[1:]
command = args[0]
state["calls"].append(args)
def finish(code=0):
    path.write_text(json.dumps(state))
    raise SystemExit(code)
if command == "list-keychains":
    if "-s" in args:
        values = args[args.index("-s") + 1:]
        if os.environ.get("TEST_RESTORE_LIST_EXIT") and not any(pathlib.Path(v).name == "mimo-signing.keychain-db" for v in values):
            finish(int(os.environ["TEST_RESTORE_LIST_EXIT"]))
        state["search"] = values
    else:
        for value in state["search"]:
            print(json.dumps(value))
elif command == "default-keychain":
    if "-s" in args:
        value = args[args.index("-s") + 1]
        if os.environ.get("TEST_RESTORE_DEFAULT_EXIT") and pathlib.Path(value).name != "mimo-signing.keychain-db":
            finish(int(os.environ["TEST_RESTORE_DEFAULT_EXIT"]))
        state["default"] = value
    else:
        print(json.dumps(state["default"]))
elif command in ("create-keychain", "delete-keychain"):
    target = pathlib.Path(args[-1])
    target.relative_to(pathlib.Path(os.environ["TEST_SIGNING_ROOT"]))
    if command == "create-keychain":
        target.write_bytes(b"temporary fixture keychain")
    else:
        target.unlink()
elif command == "import":
    if os.environ.get("TEST_IMPORT_EXIT"):
        finish(int(os.environ["TEST_IMPORT_EXIT"]))
elif command not in ("set-keychain-settings", "unlock-keychain", "set-key-partition-list"):
    finish(97)
finish()
''')

    def install_stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(body), encoding="utf-8")
        path.chmod(0o755)

    def read_state(self):
        return json.loads(self.state_path.read_text())

    def write_state(self, state):
        self.state_path.write_text(json.dumps(state))

    def run_step(self, name):
        script = workflow_run_step(name)
        # The workflow deliberately pins Apple's decoder; replace only this
        # absolute tool path with a fixture, keeping every operation/order intact.
        script = script.replace("/usr/bin/base64", str(self.bin / "base64"))
        return subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
            env=self.environment, capture_output=True, text=True, check=False,
        )

    def run_import(self):
        result = self.run_step("Import Developer ID and configure Apple notarization")
        # Simulate GitHub's transfer of GITHUB_ENV between separate steps.
        for line in self.environment_file.read_text().splitlines():
            key, value = line.split("=", 1)
            self.environment[key] = value
        return result

    def run_cleanup(self):
        return self.run_step("Remove temporary signing keychain")

    def assert_restored(self, expected_search=None):
        state = self.read_state()
        self.assertEqual(state["search"], self.originals if expected_search is None else expected_search)
        self.assertEqual(state["default"], self.original_default)
        self.assertFalse((self.runner / "mimo-signing.keychain-db").exists())
        self.assertFalse((self.runner / "mimo-developer-id.p12").exists())
        for original in self.originals:
            self.assertEqual(Path(original).read_bytes(), b"original fixture keychain")

    def test_success_preserves_original_search_list_and_default(self):
        imported = self.run_import()
        self.assertEqual(imported.returncode, 0, imported.stderr)
        self.assertEqual(self.read_state()["search"], [str(self.runner / "mimo-signing.keychain-db"), *self.originals])
        self.assertFalse((self.runner / "mimo-developer-id.p12").exists())
        cleanup = self.run_cleanup()
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assert_restored()

    def test_failed_certificate_import_still_cleans_temporary_material(self):
        self.environment["TEST_IMPORT_EXIT"] = "1"
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertFalse((self.runner / "mimo-developer-id.p12").exists())
        cleanup = self.run_cleanup()
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assert_restored()

    def test_failed_notary_configuration_restores_changed_defaults(self):
        self.environment["TEST_NOTARY_EXIT"] = "1"
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertNotEqual(self.read_state()["default"], self.original_default)
        cleanup = self.run_cleanup()
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assert_restored()

    def test_failed_search_restore_does_not_skip_default_restore_or_delete(self):
        self.assertEqual(self.run_import().returncode, 0)
        self.environment["TEST_RESTORE_LIST_EXIT"] = "1"
        cleanup = self.run_cleanup()
        self.assertNotEqual(cleanup.returncode, 0)
        self.assertEqual(self.read_state()["default"], self.original_default)
        self.assertFalse((self.runner / "mimo-signing.keychain-db").exists())
        self.assertIn("Signing cleanup failed", cleanup.stderr)

    def test_failed_default_restore_does_not_skip_delete(self):
        self.assertEqual(self.run_import().returncode, 0)
        self.environment["TEST_RESTORE_DEFAULT_EXIT"] = "1"
        cleanup = self.run_cleanup()
        self.assertNotEqual(cleanup.returncode, 0)
        self.assertEqual(self.read_state()["search"], self.originals)
        self.assertFalse((self.runner / "mimo-signing.keychain-db").exists())

    def test_empty_original_search_list_is_restored_exactly(self):
        state = self.read_state()
        state["search"] = []
        self.write_state(state)
        self.assertEqual(self.run_import().returncode, 0)
        cleanup = self.run_cleanup()
        self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
        self.assert_restored(expected_search=[])


if __name__ == "__main__":
    unittest.main()
