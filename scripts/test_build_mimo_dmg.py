#!/usr/bin/env python3
"""Exercise release packaging gates with fake macOS tools and tiny app bundles."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


SCRIPTS = Path(__file__).resolve().parent
IDENTITY = "Developer ID Application: Release Test (TESTTEAM)"

FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, shutil, signal, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
record = {"tool": name, "args": args}
if name == "build_native_app.sh":
    record["env"] = {key: os.environ.get(key) for key in [
        "MUESLI_INSTALL_DIR", "MUESLI_USE_XCODE_BUILD", "MUESLI_SKIP_SIGN",
        "MUESLI_SIGN_IDENTITY", "MUESLI_CODESIGN_TIMESTAMP",
        "MUESLI_REQUIRE_LOCALVQE", "MUESLI_ALLOW_MISSING_LOCALVQE",
    ]}
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps(record) + "\n")

def kind(path):
    if "/mounted/" in path:
        return "mounted"
    return "app" if path.endswith((".app", ".app.zip")) else "dmg"

if name == "security":
    available = os.environ.get("FAKE_AVAILABLE_ID", "Developer ID Application: Release Test (TESTTEAM)")
    if available:
        print('  1) FAKEHASH "' + available + '"')
elif name == "build_native_app.sh":
    app = pathlib.Path(os.environ["MUESLI_INSTALL_DIR"]) / "Mimo.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources/Models/localvqe").mkdir(parents=True)
    (contents / "Resources/Models/localvqe/localvqe-v1.2-1.3M-f32.gguf").write_text("model")
    if not os.environ.get("FAKE_MISSING_APPINTENTS"):
        metadata = contents / "Resources/Metadata.appintents"
        metadata.mkdir()
        (metadata / "extract.actionsdata").write_text("metadata")
    with (contents / "Info.plist").open("wb") as output:
        plistlib.dump({"CFBundleIdentifier": "com.muesli.app", "MuesliSupportDirectoryName": "Mimo", "CFBundleShortVersionString": "1.2.3"}, output)
elif name == "create_dmg.sh":
    destination = pathlib.Path(args[1])
    destination.mkdir(parents=True)
    (destination / "Mimo-1.2.3.dmg").write_text(json.dumps({"app_source": args[0]}))
elif name == "codesign":
    if "--verify" in args:
        if os.environ.get("FAKE_SIGNATURE_FAIL") == kind(args[-1]):
            sys.exit(1)
    else:
        print("CodeDirectory flags=0x10000(runtime)" if not os.environ.get("FAKE_NO_RUNTIME") else "CodeDirectory flags=0x0(none)")
        print("Authority=" + os.environ.get("FAKE_SIGNED_ID", os.environ.get("MIMO_DEVELOPER_ID", "-")))
elif name == "ditto":
    pathlib.Path(args[-1]).write_text("archive")
elif name == "cp":
    if os.environ.get("FAKE_DELIVERY_COPY_FAIL"):
        print("simulated output volume write failure", file=sys.stderr)
        sys.exit(1)
    shutil.copyfile(args[-2], args[-1])
    if os.environ.get("FAKE_DELIVERY_CORRUPT"):
        pathlib.Path(args[-1]).write_text("corrupted delivery")
    if os.environ.get("FAKE_DELIVERY_RACE"):
        (pathlib.Path(os.environ["TEST_ROOT"]) / "output/Mimo-1.2.3.dmg").write_text("concurrent release")
elif name == "xcrun":
    if args[:2] == ["notarytool", "submit"]:
        phase = kind(args[2])
        submission_id = "11111111-1111-1111-1111-" + ("000000000001" if phase == "app" else "000000000002")
        if os.environ.get("FAKE_EMPTY_SUBMIT") != phase:
            print(json.dumps({"id": submission_id, "message": "Test submission response", "path": args[2]}), flush=True)
        if os.environ.get("FAKE_CANCEL_UPLOAD") == phase:
            os.kill(os.getppid(), signal.SIGTERM)
            sys.exit(143)
        if os.environ.get("FAKE_SUBMIT_FAIL") == phase:
            print("HTTPClientError.deadlineExceeded", file=sys.stderr)
            sys.exit(1)
    elif args[:2] == ["notarytool", "wait"]:
        phase = "app" if args[2].endswith("000000000001") else "dmg"
        status = "Invalid" if os.environ.get("FAKE_REJECT_NOTARY") == phase else "Accepted"
        if os.environ.get("FAKE_WAIT_FAIL") == phase or os.environ.get("FAKE_CANCEL_NOTARY") == phase:
            print(json.dumps({"status": "In Progress", "id": args[2]}), flush=True)
            if os.environ.get("FAKE_CANCEL_NOTARY") == phase:
                os.kill(os.getppid(), signal.SIGTERM)
                sys.exit(143)
            print("Timeout reached while waiting for submission.", file=sys.stderr)
            sys.exit(69)
        submission_id = args[2] if not os.environ.get("FAKE_WRONG_RESULT_ID") else "22222222-2222-2222-2222-222222222222"
        print(json.dumps({"status": status, "id": submission_id}))
    elif args[:2] == ["notarytool", "log"]:
        phase = "app" if args[2].endswith("000000000001") else "dmg"
        if os.environ.get("FAKE_WAIT_FAIL") == phase:
            print("Submission log is not yet available.", file=sys.stderr)
            sys.exit(1)
        status = "Invalid" if os.environ.get("FAKE_REJECT_NOTARY") == phase else "Accepted"
        print(json.dumps({"status": status, "jobId": args[2], "issues": ["test rejection"] if status == "Invalid" else []}))
    elif args[:2] == ["stapler", "validate"]:
        if os.environ.get("FAKE_STAPLE_FAIL") == kind(args[-1]):
            sys.exit(1)
elif name == "spctl":
    artifact = args[-1]
    print(artifact + ": accepted")
    print("source=" + os.environ.get("FAKE_GATEKEEPER_SOURCE", "Notarized Developer ID"))
    # Deliberately print acceptance even on failure: callers must check status.
    if os.environ.get("FAKE_GATEKEEPER_FAIL") == kind(artifact):
        sys.exit(1)
elif name == "syspolicy_check":
    if args[0] != "distribution" or os.environ.get("FAKE_DISTRIBUTION_FAIL") == kind(args[-1]):
        sys.exit(1)
elif name == "hdiutil":
    if args[0] == "attach":
        mounted = pathlib.Path(args[args.index("-mountpoint") + 1])
        source = json.loads(pathlib.Path(args[1]).read_text())["app_source"]
        shutil.copytree(source, mounted / "Mimo.app")
    elif args[0] == "detach":
        mounted = pathlib.Path(args[1])
        shutil.rmtree(mounted, ignore_errors=True)
'''


class BuildMimoDMGTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mimo-packaging-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for filename in ["build_mimo_dmg.sh", "verify_notarized_artifact.sh"]:
            shutil.copy2(SCRIPTS / filename, scripts / filename)
        (scripts / "localvqe_runtime.sh").write_text(textwrap.dedent("""\
            muesli_localvqe_runtime_is_complete() {
              if [[ "$1" == */Contents/MacOS && "${FAKE_RUNTIME_FAIL:-}" == 1 ]]; then
                return 1
              fi
              return 0
            }
            """))
        fake_tool = self.root / "fake-tool"
        fake_tool.write_text(FAKE_TOOL)
        fake_tool.chmod(0o755)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ["security", "xcodegen", "codesign", "ditto", "cp", "xcrun", "spctl", "syspolicy_check", "hdiutil"]:
            (self.bin / name).symlink_to(fake_tool)
        # A closed PATH prevents a missing/new fake from invoking real Apple tools.
        for name in ["bash", "python3", "env", "dirname", "basename", "grep", "mkdir", "rm", "mktemp", "ln", "cmp"]:
            executable = shutil.which(name)
            self.assertIsNotNone(executable)
            (self.bin / name).symlink_to(executable)
        for name in ["build_native_app.sh", "create_dmg.sh", "build_localvqe.sh"]:
            (scripts / name).symlink_to(fake_tool)
        self.output = self.root / "output"
        self.work = self.root / "private-stage"
        self.log = self.root / "commands.jsonl"
        self.installed = self.root / "Applications/Mimo.app"
        self.installed.mkdir(parents=True)
        (self.installed / "existing-user-app").write_text("keep")

    def run_packager(self, **overrides):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MIMO_", "MUESLI_", "FAKE_", "TEST_"))}
        env.update({
            "PATH": str(self.bin),
            "TEST_LOG": str(self.log),
            "TEST_ROOT": str(self.root),
            "MIMO_DMG_OUTPUT_DIR": str(self.output),
            "MIMO_PACKAGE_WORK_ROOT": str(self.work),
            # Simulate a caller's installed-app target; packaging must override it.
            "MUESLI_INSTALL_DIR": str(self.installed.parent),
        })
        env.update(overrides)
        return subprocess.run(["bash", str(self.root / "scripts/build_mimo_dmg.sh")],
                              env=env, text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_no_artifacts(self, staging_retained=False):
        self.assertEqual(list(self.output.glob("*.dmg")), [])
        self.assertEqual(list(self.output.glob(".mimo-delivery.*")), [])
        self.assertEqual(list(self.output.glob(".mimo-package.*")), [])
        if staging_retained:
            self.assertTrue(list(self.work.glob(".mimo-package.*")))
        else:
            self.assertEqual(list(self.work.glob(".mimo-package.*")), [])
        self.assertEqual((self.installed / "existing-user-app").read_text(), "keep")

    def assert_no_build(self):
        self.assertFalse(any(command["tool"] == "build_native_app.sh" for command in self.commands()))
        self.assert_no_artifacts()

    def test_default_requires_developer_id_before_build(self):
        result = self.run_packager()
        self.assertEqual(result.returncode, 2)
        self.assertIn("Developer ID Application", result.stderr)
        self.assert_no_build()

    def test_apple_development_identity_is_rejected(self):
        result = self.run_packager(MIMO_DEVELOPER_ID="Apple Development: Test (TEAM)")
        self.assertEqual(result.returncode, 2)
        self.assert_no_build()

    def test_unavailable_developer_id_is_rejected(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_AVAILABLE_ID="")
        self.assertEqual(result.returncode, 2)
        self.assert_no_build()

    def test_disabling_notarization_requires_explicit_preview(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, MIMO_NOTARIZE="0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("MIMO_ALLOW_UNNOTARIZED_PREVIEW=1", result.stderr)
        self.assert_no_build()

    def test_missing_xcodegen_fails_before_build(self):
        (self.bin / "xcodegen").unlink()
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY)
        self.assertEqual(result.returncode, 2)
        self.assertIn("require Xcode and xcodegen", result.stderr)
        self.assert_no_build()

    def test_release_stages_and_forces_complete_signed_xcode_build(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, MUESLI_USE_XCODE_BUILD="0",
                                  MUESLI_SKIP_SIGN="1", MUESLI_CODESIGN_TIMESTAMP="none",
                                  MUESLI_ALLOW_MISSING_LOCALVQE="1", MUESLI_REQUIRE_LOCALVQE="0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.output / "Mimo-1.2.3.dmg").is_file())
        self.assertEqual((self.installed / "existing-user-app").read_text(), "keep")
        self.assertEqual(list(self.output.glob(".mimo-package.*")), [])
        self.assertEqual(list(self.work.glob(".mimo-package.*")), [])
        self.assertEqual(list(self.output.glob(".mimo-delivery.*")), [])
        commands = self.commands()
        build = next(command for command in commands if command["tool"] == "build_native_app.sh")
        expected = {"MUESLI_USE_XCODE_BUILD": "1", "MUESLI_SKIP_SIGN": "0",
                    "MUESLI_SIGN_IDENTITY": IDENTITY, "MUESLI_CODESIGN_TIMESTAMP": "--timestamp",
                    "MUESLI_REQUIRE_LOCALVQE": "1", "MUESLI_ALLOW_MISSING_LOCALVQE": "0"}
        for key, value in expected.items():
            self.assertEqual(build["env"][key], value)
        self.assertIn("/.mimo-package.", build["env"]["MUESLI_INSTALL_DIR"])
        self.assertTrue(Path(build["env"]["MUESLI_INSTALL_DIR"]).is_relative_to(self.work))
        self.assertFalse(Path(build["env"]["MUESLI_INSTALL_DIR"]).is_relative_to(self.output))
        delivery_copy = next(command for command in commands if command["tool"] == "cp")
        self.assertTrue(Path(delivery_copy["args"][-2]).is_relative_to(self.work))
        self.assertTrue(Path(delivery_copy["args"][-1]).is_relative_to(self.output))
        self.assertEqual(len([command for command in commands if command["tool"] == "spctl"]), 3)
        submits = [command for command in commands if command["tool"] == "xcrun" and command["args"][:2] == ["notarytool", "submit"]]
        waits = [command for command in commands if command["tool"] == "xcrun" and command["args"][:2] == ["notarytool", "wait"]]
        self.assertEqual(len(submits), 2)
        self.assertEqual(len(waits), 2)
        for command in submits:
            self.assertIn("--no-wait", command["args"])
            self.assertIn("--s3-acceleration", command["args"])
            self.assertNotIn("--wait", command["args"])
        for command in waits:
            self.assertEqual(command["args"][command["args"].index("--timeout") + 1], "20m")

    def test_explicit_preview_is_distinct_and_not_notarized(self):
        result = self.run_packager(MIMO_ALLOW_UNNOTARIZED_PREVIEW="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.output / "Mimo-1.2.3-preview.dmg").is_file())
        self.assertFalse((self.output / "Mimo-1.2.3.dmg").exists())
        self.assertIn("may be blocked by Gatekeeper", result.stdout)
        self.assertFalse(any(command["tool"] in ["spctl", "xcrun"] for command in self.commands()))

    def test_notarization_rejection_never_exposes_dmg(self):
        for kind in ["app", "dmg"]:
            with self.subTest(kind=kind):
                result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_REJECT_NOTARY=kind)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Apple did not accept", result.stderr)
                self.assert_no_artifacts(staging_retained=True)

    def test_gatekeeper_failure_never_exposes_dmg_even_with_accepted_output(self):
        for kind in ["app", "dmg", "mounted"]:
            with self.subTest(kind=kind):
                result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_GATEKEEPER_FAIL=kind)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Gatekeeper assessment failed", result.stderr)
                self.assert_no_artifacts(staging_retained=True)

    def test_non_notarized_gatekeeper_source_is_rejected(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_GATEKEEPER_SOURCE="Developer ID")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)

    def test_missing_staple_on_mounted_app_never_exposes_dmg(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_STAPLE_FAIL="mounted")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or invalid stapled", result.stderr)
        self.assert_no_artifacts(staging_retained=True)

    def test_mounted_app_distribution_failure_never_exposes_dmg(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_DISTRIBUTION_FAIL="mounted")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("App distribution assessment failed", result.stderr)
        self.assert_no_artifacts(staging_retained=True)

    def test_upload_route_override_is_explicit(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, MIMO_NOTARY_S3_ACCELERATION="0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        submits = [command for command in self.commands() if command["args"][:2] == ["notarytool", "submit"]]
        self.assertEqual(len(submits), 2)
        for command in submits:
            self.assertIn("--no-s3-acceleration", command["args"])
            self.assertNotIn("--s3-acceleration", command["args"])

    def test_invalid_upload_route_fails_before_build(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, MIMO_NOTARY_S3_ACCELERATION="sometimes")
        self.assertEqual(result.returncode, 2)
        self.assertIn("MIMO_NOTARY_S3_ACCELERATION must be 0 or 1", result.stderr)
        self.assert_no_build()

    def test_failed_upload_preserves_exact_bytes_and_does_not_wait_or_retry(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_SUBMIT_FAIL="app")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        receipts = staging / "notarization/app"
        self.assertTrue((staging / "install-root/Mimo.app").is_dir())
        self.assertEqual((staging / "Mimo.app.zip").read_text(), "archive")
        manifest = json.loads((receipts / "artifact.json").read_text())
        self.assertEqual(manifest["sha256"], hashlib.sha256(b"archive").hexdigest())
        self.assertEqual(manifest["path"], str(staging / "Mimo.app.zip"))
        self.assertIn("deadlineExceeded", (receipts / "submit.stderr.log").read_text())
        self.assertEqual((receipts / "submit.exit-code").read_text().strip(), "1")
        submission_id = json.loads((receipts / "submit.json").read_text())["id"]
        self.assertIn("Known submission: " + submission_id, result.stderr)
        self.assertIn("Upload completion was not confirmed", result.stderr)
        self.assertNotIn("continue waiting without resubmitting", result.stderr)
        self.assertFalse((receipts / "upload-completed.txt").exists())
        self.assertEqual(len([command for command in self.commands() if command["args"][:2] == ["notarytool", "submit"]]), 1)
        self.assertFalse(any(command["args"][:2] == ["notarytool", "wait"] for command in self.commands()))

    def test_upload_failure_without_id_preserves_partial_response(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_SUBMIT_FAIL="app", FAKE_EMPTY_SUBMIT="app")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        self.assertEqual((staging / "notarization/app/submit.json").read_text(), "")
        self.assertIn("No submission ID was recovered", result.stderr)
        self.assertIn("do not blindly resubmit", result.stderr)
        self.assertNotIn("Known submission:", result.stderr)
        self.assertEqual(len([command for command in self.commands() if command["args"][:2] == ["notarytool", "submit"]]), 1)

    def test_successful_upload_without_valid_receipt_fails_closed(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_EMPTY_SUBMIT="app")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        self.assertIn("Could not recover a valid submission ID", result.stderr)
        self.assertFalse(any(command["args"][:2] == ["notarytool", "wait"] for command in self.commands()))

    def test_wait_timeout_keeps_id_receipts_and_offers_waiting_without_resubmission(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_WAIT_FAIL="app")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        receipts = staging / "notarization/app"
        submission_id = (receipts / "submission-id.txt").read_text().strip()
        self.assertTrue((receipts / "upload-completed.txt").is_file())
        self.assertEqual(json.loads((receipts / "wait.json").read_text())["status"], "In Progress")
        self.assertEqual((receipts / "wait.exit-code").read_text().strip(), "69")
        self.assertIn("Timeout reached", (receipts / "wait.stderr.log").read_text())
        self.assertIn("not yet available", (receipts / "log.stderr.log").read_text())
        self.assertEqual((receipts / "log.exit-code").read_text().strip(), "1")
        self.assertIn("continue waiting without resubmitting: xcrun notarytool wait " + submission_id, result.stderr)
        self.assertEqual(len([command for command in self.commands() if command["args"][:2] == ["notarytool", "submit"]]), 1)
        self.assertEqual(len([command for command in self.commands() if command["args"][:2] == ["notarytool", "wait"]]), 1)

    def test_dmg_rejection_keeps_separate_app_and_dmg_receipts(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_REJECT_NOTARY="dmg")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        app_receipts = staging / "notarization/app"
        dmg_receipts = staging / "notarization/dmg"
        self.assertEqual(json.loads((app_receipts / "wait.json").read_text())["status"], "Accepted")
        self.assertEqual(json.loads((dmg_receipts / "wait.json").read_text())["status"], "Invalid")
        self.assertEqual(json.loads((dmg_receipts / "log.json").read_text())["issues"], ["test rejection"])
        self.assertNotEqual((app_receipts / "submission-id.txt").read_text(), (dmg_receipts / "submission-id.txt").read_text())
        self.assertTrue((staging / "dmg/Mimo-1.2.3.dmg").is_file())
        self.assertIn((dmg_receipts / "submission-id.txt").read_text().strip(), result.stderr)

    def test_cancelled_wait_keeps_staging_and_known_submission(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_CANCEL_NOTARY="app")
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        receipts = staging / "notarization/app"
        self.assertTrue((receipts / "submit.json").is_file())
        self.assertEqual(json.loads((receipts / "wait.json").read_text())["status"], "In Progress")
        self.assertIn((receipts / "submission-id.txt").read_text().strip(), result.stderr)
        self.assertEqual(len([command for command in self.commands() if command["args"][:2] == ["notarytool", "submit"]]), 1)

    def test_cancelled_upload_recovers_id_without_claiming_completion(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_CANCEL_UPLOAD="app")
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assert_no_artifacts(staging_retained=True)
        staging, = self.work.glob(".mimo-package.*")
        receipts = staging / "notarization/app"
        submission_id = json.loads((receipts / "submit.json").read_text())["id"]
        self.assertEqual((receipts / "submission-id.txt").read_text().strip(), submission_id)
        self.assertIn("Known submission: " + submission_id, result.stderr)
        self.assertIn("Upload completion was not confirmed", result.stderr)
        self.assertFalse((receipts / "upload-completed.txt").exists())
        self.assertFalse(any(command["args"][:2] == ["notarytool", "wait"] for command in self.commands()))

    def test_accepted_result_for_wrong_submission_is_rejected(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_WRONG_RESULT_ID="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)
        self.assertIn("does not match the submitted artifact", result.stderr)
        self.assertFalse(any(command["args"][:2] == ["stapler", "staple"] for command in self.commands()))

    def test_wrong_signing_identity_is_rejected(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_SIGNED_ID="Apple Development: Test")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not signed with the requested Developer ID", result.stderr)
        self.assert_no_artifacts()

    def test_missing_runtime_or_app_intents_blocks_packaging(self):
        for setting in ["FAKE_NO_RUNTIME", "FAKE_MISSING_APPINTENTS", "FAKE_RUNTIME_FAIL"]:
            with self.subTest(setting=setting):
                result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, **{setting: "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assert_no_artifacts()

    def test_existing_release_artifact_is_preserved(self):
        self.output.mkdir()
        artifact = self.output / "Mimo-1.2.3.dmg"
        artifact.write_text("already published")
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace", result.stderr)
        self.assertEqual(artifact.read_text(), "already published")

    def test_default_work_root_uses_private_temp_directory(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY,
                                  MIMO_PACKAGE_WORK_ROOT="", TMPDIR=str(self.work))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = next(command for command in self.commands() if command["tool"] == "build_native_app.sh")
        self.assertTrue(Path(build["env"]["MUESLI_INSTALL_DIR"]).is_relative_to(self.work))
        self.assertEqual(list(self.output.glob(".mimo-package.*")), [])
        self.assertEqual(list(self.output.glob(".mimo-delivery.*")), [])

    def test_relative_work_root_is_rejected_before_build(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, MIMO_PACKAGE_WORK_ROOT="relative-stage")
        self.assertEqual(result.returncode, 2)
        self.assertIn("must be an absolute directory path", result.stderr)
        self.assert_no_build()

    def test_failed_delivery_copy_is_removed_without_exposing_release(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_DELIVERY_COPY_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_artifacts(staging_retained=True)

    def test_changed_delivery_bytes_are_rejected_before_publication(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_DELIVERY_CORRUPT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("delivery copy does not match", result.stderr)
        self.assert_no_artifacts(staging_retained=True)

    def test_concurrent_release_created_during_copy_is_not_replaced(self):
        result = self.run_packager(MIMO_DEVELOPER_ID=IDENTITY, FAKE_DELIVERY_RACE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.output / "Mimo-1.2.3.dmg").read_text(), "concurrent release")
        self.assertEqual(list(self.output.glob(".mimo-delivery.*")), [])
        self.assertTrue(list(self.work.glob(".mimo-package.*")))


if __name__ == "__main__":
    unittest.main()
