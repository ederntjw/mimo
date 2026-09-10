#!/usr/bin/env python3
"""Offline regression checks for Xcode's static-XCFramework header collision."""

import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

import normalize_xcode_xcframework_headers as preparation


class XcodeHeaderPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="muesli-xcode-headers-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "SourcePackages"
        self.bundle = self.root / "artifacts/fluidaudio/NemoTextProcessing/NemoTextProcessing.xcframework"
        self.headers = {
            "module.modulemap": b'module CNemoTextProcessing { header "nemo_text_processing.h" export * }\n',
            "nemo_text_processing.h": b"void nemo_free_string(char *value);\n",
        }
        self.hashes = {name: hashlib.sha256(data).hexdigest() for name, data in self.headers.items()}
        libraries = []
        for platform in ("macos-arm64_x86_64", "ios-arm64"):
            slice_path = self.bundle / platform
            (slice_path / "Headers").mkdir(parents=True)
            for name, data in self.headers.items():
                (slice_path / "Headers" / name).write_bytes(data)
            (slice_path / "libtext_processing_rs.a").write_bytes(b"unchanged-library")
            libraries.append({"LibraryIdentifier": platform, "HeadersPath": "Headers"})
        self.plist = plistlib.dumps({"AvailableLibraries": libraries})
        (self.bundle / "Info.plist").write_bytes(self.plist)
        self.record = {
            "targetName": "NemoTextProcessing",
            "packageRef": {"identity": "fluidaudio"},
            "path": str(self.bundle),
            "source": {"url": preparation.NEMO_URL, "checksum": preparation.NEMO_CHECKSUM},
        }
        self.write_state()

    def write_state(self):
        (self.root / "workspace-state.json").write_text(json.dumps({"object": {"artifacts": [self.record]}}))

    def test_namespace_preserves_bytes_and_is_idempotent(self):
        self.assertEqual(preparation.normalize(self.root, self.hashes), 2)
        self.assertEqual(preparation.normalize(self.root, self.hashes), 0)
        for platform in ("macos-arm64_x86_64", "ios-arm64"):
            slice_path = self.bundle / platform
            headers = slice_path / "Headers"
            self.assertFalse((headers / "module.modulemap").exists())
            for name, data in self.headers.items():
                self.assertEqual((headers / preparation.NEMO_MODULE / name).read_bytes(), data)
            self.assertEqual((slice_path / "libtext_processing_rs.a").read_bytes(), b"unchanged-library")
        self.assertEqual((self.bundle / "Info.plist").read_bytes(), self.plist)

    def test_changed_header_rejected_before_any_slice_changes(self):
        (self.bundle / "ios-arm64/Headers/nemo_text_processing.h").write_bytes(b"different release")
        with self.assertRaisesRegex(ValueError, "does not match"):
            preparation.normalize(self.root, self.hashes)
        self.assertTrue((self.bundle / "macos-arm64_x86_64/Headers/module.modulemap").exists())

    def test_changed_artifact_source_rejected(self):
        self.record["source"]["checksum"] = "different-release"
        self.write_state()
        with self.assertRaisesRegex(ValueError, "Unrecognized"):
            preparation.normalize(self.root, self.hashes)

    def test_outside_cache_rejected(self):
        self.record["path"] = str(Path(self.temp.name) / "another-cache")
        self.write_state()
        with self.assertRaisesRegex(ValueError, "outside"):
            preparation.normalize(self.root, self.hashes)


if __name__ == "__main__":
    unittest.main()
