#!/usr/bin/env python3
"""Namespace the pinned NeMo headers in one Xcode DerivedData package cache.

Xcode flattens static XCFramework Headers trees into Products/<config>/include.
NeMo 0.3.0 and LiteRT-LM 0.13.1 both ship a root module.modulemap, causing two
ProcessXCFramework commands to produce the same file. Nesting NeMo's unchanged
headers avoids that collision while preserving Clang's implicit module lookup.
See https://github.com/jessegrosjean/module-map-error#how-to-fix.

Run after package resolution and before build planning. This affects only the
selected Xcode cache, never SwiftPM's shared archive or command-line/test cache.
Source identity and every header's bytes are checked before any mutation. The
binary libraries, Info.plist, module declarations, and archive checksum remain
unchanged. A new upstream artifact must be reviewed before updating these pins.
"""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import sys


NEMO_URL = "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip"
NEMO_CHECKSUM = "76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f"
NEMO_MODULE = "CNemoTextProcessing"
NEMO_HEADERS = {
    "module.modulemap": "ca0c7e3a7b4b568c13909b43632d2d4ef88a99f645b455f9dc50116bae163f24",
    "nemo_text_processing.h": "a836f3b318ca569a45abdad5b18f7543db444eb69c7115a44c05194d6f9b1300",
}


def normalize(source_packages: Path, expected_headers=None) -> int:
    """Validate all slices before moving headers; return number moved."""
    expected_headers = NEMO_HEADERS if expected_headers is None else expected_headers
    source_packages = source_packages.resolve()
    state = json.loads((source_packages / "workspace-state.json").read_text())
    artifacts = state["object"]["artifacts"]
    matches = [item for item in artifacts if item["targetName"] == "NemoTextProcessing"]
    if len(matches) != 1:
        raise ValueError("Resolve Xcode packages first: expected one NemoTextProcessing artifact")
    artifact = matches[0]
    if (artifact["packageRef"]["identity"] != "fluidaudio"
            or artifact["source"].get("url") != NEMO_URL
            or artifact["source"].get("checksum") != NEMO_CHECKSUM):
        raise ValueError("Unrecognized NeMo artifact; review its packaging before changing headers")
    bundle = Path(artifact["path"])
    if not bundle.resolve().is_relative_to(source_packages / "artifacts"):
        raise ValueError("Refusing to change an artifact outside this Xcode package cache")
    metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
    moves = []
    for library in metadata["AvailableLibraries"]:
        headers = bundle / library["LibraryIdentifier"] / library["HeadersPath"]
        if not headers.resolve().is_relative_to(bundle.resolve()) or headers.is_symlink():
            raise ValueError("Invalid NeMo header directory")
        nested = headers / NEMO_MODULE
        if nested.exists():
            if set(item.name for item in headers.iterdir()) != {NEMO_MODULE}:
                raise ValueError("Unexpected files beside normalized NeMo headers")
            active = nested
        else:
            active = headers
        if active.is_symlink() or set(item.name for item in active.iterdir()) != set(expected_headers):
            raise ValueError("Unexpected NeMo header layout")
        for filename, checksum in expected_headers.items():
            header = active / filename
            if header.is_symlink() or hashlib.sha256(header.read_bytes()).hexdigest() != checksum:
                raise ValueError(f"NeMo header does not match the pinned release: {filename}")
        if active == headers:
            moves.append((headers, nested))
    for headers, nested in moves:
        nested.mkdir()
        for filename in expected_headers:
            (headers / filename).rename(nested / filename)
    return len(moves)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_packages", type=Path)
    args = parser.parse_args()
    try:
        count = normalize(args.source_packages)
    except (OSError, ValueError, KeyError) as error:
        print(f"Xcode XCFramework preparation failed: {error}", file=sys.stderr)
        return 1
    print(f"Validated NeMo XCFramework headers ({count} slices namespaced for Xcode).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
