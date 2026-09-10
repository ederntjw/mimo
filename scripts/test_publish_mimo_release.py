#!/usr/bin/env python3
"""Exercise publication ordering without credentials, network access, or a Mac build."""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.8.6"
TAG = f"v{VERSION}"
DMG = f"Mimo-{VERSION}.dmg"
FEED = "https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml"

FAKE_GH = r'''#!/usr/bin/env python3
import json
import os
import shutil
import sys
from pathlib import Path

args = sys.argv[1:]
with open(os.environ["MOCK_CALLS"], "a") as log:
    log.write(json.dumps(["gh", *args]) + "\n")
state_path = Path(os.environ["MOCK_STATE"])
state = json.loads(state_path.read_text()) if state_path.exists() else {}
assets = Path(os.environ["MOCK_ASSETS"])
if args[0] == "api":
    assert "--paginate" in args
    assert "repos/ederntjw/mimo/releases?per_page=100" in args
    assert args[args.index("--jq") + 1] == ".[].tag_name"
    if os.environ.get("MOCK_LOOKUP_FAILURE"):
        sys.exit(7)
    if state:
        print(state["tag"])
elif args[:2] == ["release", "create"]:
    assert not state, "Existing release must not be replaced"
    assert "--draft" in args and "--latest" not in args
    assert args[args.index("--target") + 1] == os.environ["GITHUB_SHA"]
    assert args[args.index("--repo") + 1] == "ederntjw/mimo"
    assert Path(args[args.index("--notes-file") + 1]).is_file()
    assets.mkdir()
    for asset in args:
        if "#" in asset:
            path = Path(asset.split("#", 1)[0])
            shutil.copyfile(path, assets / path.name)
    state = {"tag": args[2], "draft": True}
    state_path.write_text(json.dumps(state))
elif args[:2] == ["release", "download"]:
    assert state["draft"]
    if os.environ.get("MOCK_DOWNLOAD_FAILURE"):
        sys.exit(8)
    destination = Path(args[args.index("--dir") + 1])
    patterns = [args[i + 1] for i, arg in enumerate(args) if arg == "--pattern"]
    assert set(patterns) == {"Mimo-0.8.6.dmg", "Mimo-0.8.6.dmg.sha256", "appcast.xml"}
    for name in patterns:
        shutil.copyfile(assets / name, destination / name)
    corrupt = os.environ.get("MOCK_CORRUPT_ASSET")
    if corrupt:
        with (destination / corrupt).open("ab") as output:
            output.write(b"corrupt upload")
elif args[:2] == ["release", "edit"]:
    assert state["draft"]
    assert "--draft=false" in args and "--latest" in args
    assert args[args.index("--repo") + 1] == "ederntjw/mimo"
    state["draft"] = False
    state_path.write_text(json.dumps(state))
else:
    raise AssertionError(f"Unexpected gh operation: {args}")
'''

FAKE_VERIFIER = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
with open(os.environ["MOCK_CALLS"], "a") as log:
    log.write(json.dumps(["verify", *args]) + "\n")
assert "--require-notarized" in args
assert "--require-release-notes" in args
assert "--skip-dmg" not in args
for option in ("--dmg", "--appcast"):
    path = Path(args[args.index(option) + 1])
    assert path.is_file()
    assert path.parent != Path(os.environ["OUTPUT_DIR"])
sys.exit(9 if os.environ.get("MOCK_VERIFIER_REJECT") else 0)
'''


class PublishMimoReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mimo publication test ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / "repository"
        self.repo.mkdir()
        self.output = self.repo / "release output"
        self.output.mkdir()
        (self.output / DMG).write_bytes(b"Final stapled DMG fixture\x00\xff")
        (self.output / "appcast.xml").write_text("<rss>signed feed fixture</rss>\n")
        scripts = self.repo / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts/publish_mimo_release.sh", scripts)
        self.write_executable(scripts / "verify_update_flow.sh", FAKE_VERIFIER)
        notes = self.repo / "docs/release-notes"
        notes.mkdir(parents=True)
        (notes / f"{VERSION}.md").write_text("Mimo release fixture notes.\n")
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.write_executable(self.bin / "gh", FAKE_GH)
        self.git("init", "--quiet")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "--quiet", "--allow-empty", "-m", "Release source")
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.remote = self.base / "remote.git"
        subprocess.run(["git", "init", "--bare", "--quiet", str(self.remote)], check=True)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "--quiet", "origin", "HEAD:refs/heads/main")
        self.calls_path = self.base / "calls.jsonl"
        self.state_path = self.base / "release.json"
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "RELEASE_VERSION": VERSION,
            "RELEASE_TAG": TAG,
            "GITHUB_SHA": self.sha,
            "OUTPUT_DIR": str(self.output),
            "TMPDIR": str(self.base),
            "MOCK_CALLS": str(self.calls_path),
            "MOCK_STATE": str(self.state_path),
            "MOCK_ASSETS": str(self.base / "uploaded assets"),
        }

    @staticmethod
    def write_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout

    def run_helper(self, **overrides: str) -> subprocess.CompletedProcess:
        return subprocess.run([str(self.repo / "scripts/publish_mimo_release.sh")],
                              cwd=self.repo, env={**self.env, **overrides},
                              capture_output=True, text=True)

    def calls(self) -> list:
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def assert_unpublished_draft(self, result: subprocess.CompletedProcess) -> None:
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(json.loads(self.state_path.read_text())["draft"])
        self.assertFalse(any(call[1:3] == ["release", "edit"] for call in self.calls()))
        self.assertFalse(any("delete" in call for call in self.calls()))

    def test_downloaded_assets_are_verified_before_publication(self) -> None:
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(self.state_path.read_text())["draft"])
        calls = self.calls()
        self.assertEqual([call[:3] if call[0] == "gh" else call[:1] for call in calls], [
            ["gh", "api", "--paginate"], ["gh", "release", "create"],
            ["gh", "release", "download"], ["verify"], ["gh", "release", "edit"],
        ])
        verification = next(call for call in calls if call[0] == "verify")
        for option, expected in {
            "--version": VERSION, "--short-version": VERSION,
            "--artifact-version": VERSION, "--app-name": "Mimo",
            "--feed-url": FEED, "--github-repository": "ederntjw/mimo",
            "--release-tag": TAG,
        }.items():
            self.assertEqual(verification[verification.index(option) + 1], expected)
        checksum = (self.output / f"{DMG}.sha256").read_text()
        digest = hashlib.sha256((self.output / DMG).read_bytes()).hexdigest()
        self.assertEqual(checksum, f"{digest}  {DMG}\n")
        # The sidecar works as downloaded, without its original build directory.
        downloaded = self.base / "uploaded assets"
        result = subprocess.run(["shasum", "-a", "256", "-c", f"{DMG}.sha256"],
                                cwd=downloaded, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_annotated_tag_is_compared_by_commit(self) -> None:
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "tag", "-a", TAG, "-m", "Release tag")
        self.git("push", "--quiet", "origin", f"refs/tags/{TAG}")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_each_corrupt_uploaded_asset_prevents_publication(self) -> None:
        for asset in (DMG, f"{DMG}.sha256", "appcast.xml"):
            with self.subTest(asset=asset):
                if self.state_path.exists():
                    self.state_path.unlink()
                    self.calls_path.unlink()
                    shutil.rmtree(self.base / "uploaded assets")
                result = self.run_helper(MOCK_CORRUPT_ASSET=asset)
                self.assert_unpublished_draft(result)
                self.assertFalse(any(call[0] == "verify" for call in self.calls()))

    def test_verifier_rejection_prevents_publication(self) -> None:
        self.assert_unpublished_draft(self.run_helper(MOCK_VERIFIER_REJECT="1"))
        self.assertTrue(any(call[0] == "verify" for call in self.calls()))

    def test_download_failure_leaves_draft(self) -> None:
        self.assert_unpublished_draft(self.run_helper(MOCK_DOWNLOAD_FAILURE="1"))

    def test_existing_draft_or_published_release_is_never_replaced(self) -> None:
        for draft in (True, False):
            with self.subTest(draft=draft):
                self.state_path.write_text(json.dumps({"tag": TAG, "draft": draft}))
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(json.loads(self.state_path.read_text())["draft"], draft)
                self.assertTrue(all(call[1] == "api" for call in self.calls()))

    def test_release_lookup_failure_stops_before_creation(self) -> None:
        result = self.run_helper(MOCK_LOOKUP_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state_path.exists())
        self.assertEqual(len(self.calls()), 1)

    def test_remote_tag_mismatch_stops_before_creation_even_without_local_tag(self) -> None:
        self.git("tag", TAG)
        self.git("push", "--quiet", "origin", f"refs/tags/{TAG}")
        self.git("tag", "-d", TAG)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "--quiet", "--allow-empty", "-m", "Another commit")
        result = self.run_helper(GITHUB_SHA=self.git("rev-parse", "HEAD").strip())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Remote release tag does not match", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_checked_out_source_must_match_github_sha(self) -> None:
        result = self.run_helper(GITHUB_SHA="0" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
