#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FEED_URL = "https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml"
PUBLIC_KEY = "5YCc2MtI+BSleheL65Le6rsFk6Ynw+k+19/KOcc60BY="


class MimoUpdateFlowTests(unittest.TestCase):
    def test_mimo_build_enables_owned_signed_feed(self) -> None:
        script = (ROOT / "scripts/build_mimo_dmg.sh").read_text(encoding="utf-8")
        self.assertIn(FEED_URL, script)
        self.assertIn(PUBLIC_KEY, script)
        self.assertNotIn("MUESLI_SPARKLE_FEED_URL=\n", script)

    def test_release_workflow_uses_secret_and_never_contains_private_key(self) -> None:
        workflow = (ROOT / ".github/workflows/mimo-release.yml").read_text(encoding="utf-8")
        self.assertIn("secrets.MIMO_SPARKLE_PRIVATE_KEY", workflow)
        self.assertIn("--ed-key-file -", workflow)
        self.assertIn("./scripts/publish_mimo_release.sh", workflow)
        self.assertIn(FEED_URL, workflow)
        self.assertIn('MIMO_NOTARIZE: "1"', workflow)
        self.assertIn("--require-notarized", workflow)
        self.assertIn("MIMO_DEVELOPER_ID_CERTIFICATE_BASE64", workflow)
        self.assertIn("MIMO_SUPABASE_PUBLISHABLE_KEY", workflow)
        self.assertNotIn("MIMO_SPARKLE_PRIVATE_KEY: 5", workflow)

    def test_verifier_accepts_mimo_repository_contract(self) -> None:
        signature = base64.b64encode(bytes(64)).decode("ascii")
        appcast = f'''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>0.8.5</title>
      <description>Mimo update test release notes.</description>
      <sparkle:version>0.8.5</sparkle:version>
      <sparkle:shortVersionString>0.8.5</sparkle:shortVersionString>
      <enclosure url="https://github.com/ederntjw/mimo/releases/download/v0.8.5/Mimo-0.8.5.dmg" length="42" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(appcast, encoding="utf-8")
            result = subprocess.run(
                [
                    str(ROOT / "scripts/verify_update_flow.sh"),
                    "--version", "0.8.5",
                    "--short-version", "0.8.5",
                    "--artifact-version", "0.8.5",
                    "--appcast", str(path),
                    "--app-name", "Mimo",
                    "--feed-url", FEED_URL,
                    "--github-repository", "ederntjw/mimo",
                    "--release-tag", "v0.8.5",
                    "--require-release-notes",
                    "--skip-dmg",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_ci_packaging_disables_finder_and_uploads_only_safe_receipts(self) -> None:
        workflow = (ROOT / ".github/workflows/mimo-release.yml").read_text(encoding="utf-8")
        self.assertIn('MUESLI_DMG_CONFIGURE_FINDER: "0"', workflow)
        self.assertIn("MIMO_PACKAGE_WORK_ROOT: ${{ runner.temp }}/mimo-package-work", workflow)
        section = workflow.split("      - name: Retain safe notarization recovery receipts\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("failure() || cancelled()", section)
        self.assertIn("path: ${{ runner.temp }}/mimo-notary-receipts", section)
        self.assertNotIn("mimo-package-work", section)
        recovery = workflow.split("      - name: Retain package artifacts for notarization recovery only\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("failure() || cancelled()", recovery)
        self.assertIn("path: ${{ runner.temp }}/mimo-notarization-recovery", recovery)
        self.assertIn("name: mimo-notarization-recovery-", recovery)
        self.assertIn("retention-days: 3", recovery)
        self.assertNotIn("mimo-package-work", recovery)

    def test_failure_receipts_keep_hash_status_and_exclude_sensitive_raw_output(self) -> None:
        workflow = (ROOT / ".github/workflows/mimo-release.yml").read_text(encoding="utf-8")
        section = workflow.split("      - name: Prepare safe notarization recovery receipts\n", 1)[1].split("\n      - name:", 1)[0]
        script = textwrap.dedent(section.split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory(prefix="mimo-safe-receipts-") as temporary:
            base = Path(temporary)
            work = base / "work"
            phase = work / ".mimo-package.fixture/notarization/app"
            phase.mkdir(parents=True)
            identifier = "11111111-1111-1111-1111-111111111111"
            secret = "DO-NOT-UPLOAD-FIXTURE-SECRET"
            (phase / "artifact.json").write_text(json.dumps({"path": "/private/source/Mimo.app.zip", "sha256": "a" * 64}))
            (phase / "submit.json").write_text(json.dumps({"id": identifier, "message": secret, "url": "https://s3.example.invalid/?signature=" + secret}))
            (phase / "wait.json").write_text(json.dumps({"id": identifier, "status": "In Progress", "password": secret}))
            (phase / "log.json").write_text(json.dumps({"jobId": identifier, "status": "In Progress", "issues": [{"message": secret}]}))
            (phase / "submit.exit-code").write_text("0\n")
            (phase / "wait.exit-code").write_text("69\n")
            (phase / "submission-id.txt").write_text(identifier)
            (phase / "upload-completed.txt").write_text("Upload complete")
            (phase / "upload-route.txt").write_text("--no-s3-acceleration")
            (phase / "submit.stderr.log").write_text("HTTPClientError.deadlineExceeded https://s3.example.invalid/?signature=" + secret)
            (phase / "private-key.p12").write_text(secret)
            (base / "mimo-signing.keychain-db").write_text(secret)
            output = base / "github-output"
            environment = {"PATH": os.environ["PATH"], "MIMO_PACKAGE_WORK_ROOT": str(work), "RUNNER_TEMP": str(base), "GITHUB_OUTPUT": str(output)}
            result = subprocess.run(["/bin/bash", "-e", "-c", script], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = list((base / "mimo-notary-receipts").iterdir())
            self.assertEqual([p.name for p in files], ["01-app.json"])
            text = files[0].read_text()
            self.assertNotIn(secret, text)
            self.assertNotIn("https://", text)
            self.assertNotIn("/private/source", text)
            receipt = json.loads(text)
            self.assertEqual(receipt["sha256"], "a" * 64)
            self.assertEqual(receipt["submissionID"], identifier)
            self.assertEqual(receipt["responses"]["wait"]["status"], "In Progress")
            self.assertEqual(receipt["exitCodes"]["wait"], 69)
            self.assertEqual(receipt["diagnosticCategories"], ["HTTPClientError.deadlineExceeded"])
            self.assertTrue(receipt["uploadCompleted"])
            self.assertIn("has_receipts=true", output.read_text())
            self.assertIn("has_recovery_artifacts=false", output.read_text())
            self.assertFalse((base / "mimo-notarization-recovery").exists())

            # An ID allocation or even an interrupted marker is not proof the
            # upload succeeded; malformed responses must not expose raw text.
            (phase / "submit.exit-code").write_text("1\n")
            (phase / "submit.json").write_text(secret)
            second = subprocess.run(["/bin/bash", "-e", "-c", script], env=environment, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertFalse(json.loads(files[0].read_text())["uploadCompleted"])

    def test_recovery_preserves_only_exact_package_paths_and_records_retained_bytes(self) -> None:
        workflow = (ROOT / ".github/workflows/mimo-release.yml").read_text(encoding="utf-8")
        section = workflow.split("      - name: Prepare safe notarization recovery receipts\n", 1)[1].split("\n      - name:", 1)[0]
        script = textwrap.dedent(section.split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory(prefix="mimo-package-recovery-") as temporary:
            base = Path(temporary)
            work = base / "work"
            secret = b"DO-NOT-UPLOAD-FIXTURE-SECRET"

            def receipt(stage_name: str, phase_name: str, artifact_path: Path, digest: str) -> None:
                phase = work / stage_name / "notarization" / phase_name
                phase.mkdir(parents=True)
                (phase / "artifact.json").write_text(json.dumps({"path": str(artifact_path), "sha256": digest}))
                (phase / "submit.stderr.log").write_bytes(secret)
                (phase / "signing.p12").write_bytes(secret)
                (phase / "config.json").write_bytes(secret)

            stage = work / ".mimo-package.valid"
            (stage / "dmg").mkdir(parents=True)
            app = stage / "Mimo.app.zip"
            dmg = stage / "dmg/Mimo-0.8.5.dmg"
            app.write_bytes(b"exact signed app zip fixture")
            dmg.write_bytes(b"exact accepted and stapled dmg fixture")
            app_digest = hashlib.sha256(app.read_bytes()).hexdigest()
            receipt(stage.name, "app", app, app_digest)
            # Stapling can change the DMG after submission; keep both hashes.
            receipt(stage.name, "dmg", dmg, "a" * 64)
            (stage / "Mimo-other.zip").write_bytes(secret)
            (stage / "signing.keychain-db").write_bytes(secret)

            outside = base / "Mimo-9.9.9.dmg"
            outside.write_bytes(secret)
            receipt(".mimo-package.escape", "dmg", outside, "b" * 64)
            symlink = work / ".mimo-package.symlink/Mimo.app.zip"
            symlink.parent.mkdir(parents=True)
            symlink.symlink_to(outside)
            receipt(symlink.parent.name, "app", symlink, "b" * 64)
            linked_directory = work / ".mimo-package.parent-link"
            linked_directory.mkdir(parents=True)
            (linked_directory / "dmg").symlink_to(base, target_is_directory=True)
            receipt(linked_directory.name, "dmg", linked_directory / "dmg" / outside.name, "b" * 64)
            forbidden = work / ".mimo-package.wrong-name/signing.p12"
            forbidden.parent.mkdir(parents=True)
            forbidden.write_bytes(secret)
            receipt(forbidden.parent.name, "app", forbidden, "b" * 64)

            output = base / "github-output"
            environment = {"PATH": os.environ["PATH"], "MIMO_PACKAGE_WORK_ROOT": str(work), "RUNNER_TEMP": str(base), "GITHUB_OUTPUT": str(output)}
            result = subprocess.run(["/bin/bash", "-e", "-c", script], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            recovery = base / "mimo-notarization-recovery"
            files = sorted(path for path in recovery.rglob("*") if path.is_file())
            self.assertEqual(sorted(path.name for path in files), ["Mimo-0.8.5.dmg", "Mimo.app.zip", "README.txt", "receipt.json", "receipt.json"])
            for path in files:
                self.assertNotIn(secret, path.read_bytes())
            for original in [app, dmg]:
                copied = next(path for path in files if path.name == original.name)
                self.assertEqual(copied.read_bytes(), original.read_bytes())
                safe = json.loads((copied.parent / "receipt.json").read_text())
                self.assertEqual(safe["recoveryArtifactName"], original.name)
                self.assertEqual(safe["recoveryArtifactSha256"], hashlib.sha256(copied.read_bytes()).hexdigest())
                self.assertEqual(safe["sha256"], app_digest if original == app else "a" * 64)
            self.assertIn("has_recovery_artifacts=true", output.read_text())
            self.assertIn("not a published release", (recovery / "README.txt").read_text())


if __name__ == "__main__":
    unittest.main()
