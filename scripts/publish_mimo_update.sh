#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/publish_mimo_update.sh <version>

Creates and pushes an annotated v<version> tag. The Publish Mimo update GitHub
workflow builds the DMG, signs its Sparkle appcast, publishes the GitHub Release,
and moves Mimo's stable update feed to that release.

Before running:
  1. Commit the update and docs/release-notes/<version>.md on main.
  2. Push main and wait for CI to pass.
  3. Run this script, for example: ./scripts/publish_mimo_update.sh 0.8.6
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  usage
  echo "ERROR: version must be numeric x.y.z" >&2
  exit 2
fi

cd "$ROOT"
TAG="v$VERSION"
NOTES="docs/release-notes/$VERSION.md"

if [[ ! -f "$NOTES" ]]; then
  echo "ERROR: missing $NOTES" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: commit tracked changes before publishing an update." >&2
  exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "ERROR: publish updates from main after CI has passed." >&2
  exit 1
fi

git fetch origin main --tags --quiet
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "ERROR: local main and origin/main must point to the same commit." >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ERROR: tag $TAG already exists." >&2
  exit 1
fi

git tag -a "$TAG" -m "Mimo $VERSION"
git push origin "$TAG"

echo
echo "Mimo $VERSION is building at:"
echo "https://github.com/ederntjw/mimo/actions/workflows/mimo-release.yml"
