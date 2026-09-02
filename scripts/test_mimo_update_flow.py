#!/usr/bin/env python3
import base64
import subprocess
import tempfile
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
        self.assertIn("--latest", workflow)
        self.assertIn(FEED_URL, workflow)
        self.assertIn('MIMO_NOTARIZE: "1"', workflow)
        self.assertIn("--require-notarized", workflow)
        self.assertIn("MIMO_DEVELOPER_ID_CERTIFICATE_BASE64", workflow)
        self.assertIn("MIMO_SUPABASE_PUBLISHABLE_KEY", workflow)
        self.assertNotIn("MIMO_SPARKLE_PRIVATE_KEY: 5", workflow)

    def test_preview_and_notarized_dmg_modes_are_explicit(self) -> None:
        script = (ROOT / "scripts/build_mimo_dmg.sh").read_text(encoding="utf-8")
        self.assertIn("MIMO_NOTARIZE=1 requires MIMO_DEVELOPER_ID", script)
        self.assertIn('notarize_artifact "$APP_ZIP" "Mimo.app"', script)
        self.assertIn('notarize_artifact "$DMG_PATH"', script)
        self.assertIn('xcrun stapler validate "$DMG_PATH"', script)

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


if __name__ == "__main__":
    unittest.main()
