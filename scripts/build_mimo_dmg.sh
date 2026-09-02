#!/usr/bin/env bash
set -euo pipefail

# Builds the desktop app as Mimo, installs it in /Applications, and produces a
# drag-to-Applications DMG. With no Developer ID configured, the output is
# ad-hoc signed for preview distribution and macOS will require Open/confirm.
# With MIMO_NOTARIZE=1, the Developer ID-signed app and DMG are both submitted
# to Apple, stapled, and validated before this script succeeds.
#
# Notarized build inputs:
#   MIMO_DEVELOPER_ID="Developer ID Application: ..." \
#   MIMO_NOTARIZE=1 \
#   MUESLI_NOTARY_PROFILE=MimoNotary \
#   ./scripts/build_mimo_dmg.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/localvqe_runtime.sh"

OUTPUT_DIR="${MIMO_DMG_OUTPUT_DIR:-$ROOT/dist-share}"
SPARKLE_FEED_URL="${MIMO_SPARKLE_FEED_URL:-https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${MIMO_SPARKLE_PUBLIC_KEY:-5YCc2MtI+BSleheL65Le6rsFk6Ynw+k+19/KOcc60BY=}"
USE_XCODE_BUILD="${MUESLI_USE_XCODE_BUILD:-}"
NOTARIZE="${MIMO_NOTARIZE:-0}"
NOTARY_PROFILE="${MUESLI_NOTARY_PROFILE:-MimoNotary}"
NOTARY_TEMP_DIR=""

cleanup() {
  if [[ -n "$NOTARY_TEMP_DIR" && -d "$NOTARY_TEMP_DIR" ]]; then
    rm -rf "$NOTARY_TEMP_DIR"
  fi
}
trap cleanup EXIT

notarize_artifact() {
  local artifact="$1"
  local label="$2"
  local output
  echo "Submitting $label to Apple notarization..."
  if ! output=$(xcrun notarytool submit "$artifact" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait 2>&1); then
    echo "$output" >&2
    echo "ERROR: Apple notarization request failed for $label" >&2
    exit 1
  fi
  echo "$output"
  if ! grep -q "status: Accepted" <<< "$output"; then
    local submission_id
    submission_id=$(awk '/^[[:space:]]*id:/ {print $2; exit}' <<< "$output")
    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "$submission_id" \
        --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
    fi
    echo "ERROR: Apple did not accept $label" >&2
    exit 1
  fi
}

if [[ -z "$USE_XCODE_BUILD" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    USE_XCODE_BUILD=1
  else
    USE_XCODE_BUILD=0
  fi
fi

if ! muesli_localvqe_runtime_is_complete "$ROOT/native/MuesliNative/LocalVQE/lib"; then
  echo "LocalVQE runtime is incomplete; building it now..."
  "$ROOT/scripts/build_localvqe.sh"
fi

BUILD_ENV=(
  MUESLI_APP_NAME=Mimo
  MUESLI_DISPLAY_NAME=Mimo
  MUESLI_APP_BUNDLE_NAME=Mimo.app
  MUESLI_EXECUTABLE_NAME=Mimo
  MUESLI_SUPPORT_DIR_NAME=Mimo
  MUESLI_BUNDLE_ID=com.muesli.app
  MUESLI_SPARKLE_FEED_URL="$SPARKLE_FEED_URL"
  MUESLI_SPARKLE_EDKEY="$SPARKLE_PUBLIC_KEY"
  MUESLI_USE_XCODE_BUILD="$USE_XCODE_BUILD"
)

DMG_IDENTITY="-"
if [[ -n "${MIMO_DEVELOPER_ID:-}" ]]; then
  BUILD_ENV+=(
    MUESLI_SKIP_SIGN=0
    MUESLI_SIGN_IDENTITY="$MIMO_DEVELOPER_ID"
  )
  if [[ -z "${MUESLI_PROVISIONING_PROFILE:-}" ]]; then
    # Mimo Account is the cross-platform sync path. A release without an
    # explicit legacy CloudKit profile uses the local-only entitlement set.
    BUILD_ENV+=(MUESLI_ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements")
  fi
  DMG_IDENTITY="$MIMO_DEVELOPER_ID"
else
  BUILD_ENV+=(
    # Keep preview apps internally consistent: Sparkle, frameworks, helper
    # executables, and the app itself all receive the same ad-hoc signature.
    # This is still not a substitute for Developer ID + notarization.
    MUESLI_SKIP_SIGN=0
    MUESLI_SIGN_IDENTITY="-"
    MUESLI_CODESIGN_TIMESTAMP="none"
    MUESLI_ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements"
  )
fi

if [[ "$NOTARIZE" == "1" && "$DMG_IDENTITY" == "-" ]]; then
  echo "ERROR: MIMO_NOTARIZE=1 requires MIMO_DEVELOPER_ID." >&2
  exit 2
fi

env "${BUILD_ENV[@]}" "$ROOT/scripts/build_native_app.sh" release

if [[ "$NOTARIZE" == "1" ]]; then
  NOTARY_TEMP_DIR=$(mktemp -d)
  APP_ZIP="$NOTARY_TEMP_DIR/Mimo.app.zip"
  ditto -c -k --sequesterRsrc --keepParent /Applications/Mimo.app "$APP_ZIP"
  notarize_artifact "$APP_ZIP" "Mimo.app"
  xcrun stapler staple /Applications/Mimo.app
  xcrun stapler validate /Applications/Mimo.app
fi

MUESLI_SIGN_IDENTITY="$DMG_IDENTITY" "$ROOT/scripts/create_dmg.sh" "/Applications/Mimo.app" "$OUTPUT_DIR"

if [[ "$NOTARIZE" == "1" ]]; then
  DMG_PATH="$OUTPUT_DIR/Mimo-${MUESLI_SHORT_VERSION:-${MUESLI_BUILD_VERSION:-0.8.6}}.dmg"
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "ERROR: expected DMG was not created at $DMG_PATH" >&2
    exit 1
  fi
  notarize_artifact "$DMG_PATH" "$(basename "$DMG_PATH")"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo
echo "Mimo DMG ready in: $OUTPUT_DIR"
echo "Sparkle update feed: $SPARKLE_FEED_URL"
if [[ "$NOTARIZE" == "1" ]]; then
  echo "Apple notarization: accepted and stapled"
elif [[ "$DMG_IDENTITY" == "-" ]]; then
  echo "This preview DMG is ad-hoc signed and not notarized. Friends may need to right-click Mimo and choose Open once."
fi
