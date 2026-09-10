#!/usr/bin/env bash
set -euo pipefail

# Called by mimo-release.yml after building, notarizing, and signing the appcast.
# A failed check intentionally leaves the release as a draft for investigation.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="ederntjw/mimo"
FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
RELEASE_VERSION="${RELEASE_VERSION:?RELEASE_VERSION is required}"
RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
GITHUB_SHA="${GITHUB_SHA:?GITHUB_SHA is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Release version must be numeric x.y.z."
[[ "$RELEASE_TAG" == "v$RELEASE_VERSION" ]] || fail "Release tag must match the version."
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "GITHUB_SHA must be a full commit SHA."

cd "$ROOT"
[[ "$(git rev-parse --verify HEAD)" == "$GITHUB_SHA" ]] || fail "Checked-out source does not match GITHUB_SHA."
if git show-ref --verify --quiet "refs/tags/$RELEASE_TAG"; then
  [[ "$(git rev-parse --verify "refs/tags/$RELEASE_TAG^{commit}")" == "$GITHUB_SHA" ]] \
    || fail "Local release tag does not match GITHUB_SHA."
fi
# Inspect the remote too: a shallow checkout or manual dispatch may lack its tag.
# Annotated tags use their peeled commit, not their tag object's SHA.
if ! REMOTE_TAG_REFS=$(git ls-remote --tags origin "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}"); then
  fail "Could not validate the remote release tag."
fi
REMOTE_TAG_SHA=$(awk -v tag="refs/tags/$RELEASE_TAG" '
  $2 == tag { direct = $1 }
  $2 == tag "^{}" { peeled = $1 }
  END { print peeled ? peeled : direct }
' <<< "$REMOTE_TAG_REFS")
[[ -z "$REMOTE_TAG_SHA" || "$REMOTE_TAG_SHA" == "$GITHUB_SHA" ]] \
  || fail "Remote release tag does not match GITHUB_SHA."

OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
DMG_NAME="Mimo-$RELEASE_VERSION.dmg"
CHECKSUM_NAME="$DMG_NAME.sha256"
NOTES_PATH="$ROOT/docs/release-notes/$RELEASE_VERSION.md"
for artifact in "$OUTPUT_DIR/$DMG_NAME" "$OUTPUT_DIR/appcast.xml" "$NOTES_PATH"; do
  [[ -s "$artifact" ]] || fail "Missing or empty release input: $artifact"
done

# Paginate so an older published release or an existing draft is never replaced.
# An authentication/network failure must not be interpreted as an absent release.
if ! EXISTING_TAGS=$(gh api --paginate "repos/$REPOSITORY/releases?per_page=100" --jq '.[].tag_name'); then
  fail "Could not check existing releases."
fi
if grep -Fxq -- "$RELEASE_TAG" <<< "$EXISTING_TAGS"; then
  fail "Release $RELEASE_TAG already exists; refusing to replace its assets."
fi

# Use a basename so recipients can verify both adjacent downloads with shasum -c.
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$DMG_NAME" > "$CHECKSUM_NAME"
)

VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mimo-release-verify.XXXXXX")
cleanup() {
  rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

gh release create "$RELEASE_TAG" \
  "$OUTPUT_DIR/$DMG_NAME#Mimo $RELEASE_VERSION DMG" \
  "$OUTPUT_DIR/$CHECKSUM_NAME#SHA-256 checksum" \
  "$OUTPUT_DIR/appcast.xml#Sparkle update feed" \
  --repo "$REPOSITORY" \
  --draft \
  --target "$GITHUB_SHA" \
  --title "Mimo $RELEASE_VERSION" \
  --notes-file "$NOTES_PATH"

echo "Draft created. It will remain unpublished unless every downloaded-artifact check succeeds."
gh release download "$RELEASE_TAG" \
  --repo "$REPOSITORY" \
  --dir "$VERIFY_DIR" \
  --pattern "$DMG_NAME" \
  --pattern "$CHECKSUM_NAME" \
  --pattern appcast.xml

for artifact_name in "$DMG_NAME" "$CHECKSUM_NAME" appcast.xml; do
  cmp -s "$OUTPUT_DIR/$artifact_name" "$VERIFY_DIR/$artifact_name" \
    || fail "Downloaded $artifact_name differs from the verified local artifact; keeping the draft unpublished."
done

"$ROOT/scripts/verify_update_flow.sh" \
  --version "$RELEASE_VERSION" \
  --short-version "$RELEASE_VERSION" \
  --artifact-version "$RELEASE_VERSION" \
  --appcast "$VERIFY_DIR/appcast.xml" \
  --dmg "$VERIFY_DIR/$DMG_NAME" \
  --app-name Mimo \
  --feed-url "$FEED_URL" \
  --github-repository "$REPOSITORY" \
  --release-tag "$RELEASE_TAG" \
  --require-release-notes \
  --require-notarized

gh release edit "$RELEASE_TAG" --repo "$REPOSITORY" --draft=false --latest
echo "Published Mimo $RELEASE_VERSION after verifying the uploaded release assets."
