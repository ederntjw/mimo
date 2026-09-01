#!/usr/bin/env bash
set -euo pipefail

# Builds the desktop app as Mimo, installs it in /Applications, and produces a
# drag-to-Applications DMG. With no Developer ID configured, the output is
# ad-hoc signed for preview distribution and macOS will require Open/confirm.
#
# Optional notarized build inputs:
#   MIMO_DEVELOPER_ID="Developer ID Application: ..." \
#   MUESLI_PROVISIONING_PROFILE=/path/to/profile.provisionprofile \
#   ./scripts/build_mimo_dmg.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/localvqe_runtime.sh"

OUTPUT_DIR="${MIMO_DMG_OUTPUT_DIR:-$ROOT/dist-share}"
USE_XCODE_BUILD="${MUESLI_USE_XCODE_BUILD:-}"
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
  MUESLI_SPARKLE_FEED_URL=
  MUESLI_USE_XCODE_BUILD="$USE_XCODE_BUILD"
)

DMG_IDENTITY="-"
if [[ -n "${MIMO_DEVELOPER_ID:-}" ]]; then
  BUILD_ENV+=(
    MUESLI_SKIP_SIGN=0
    MUESLI_SIGN_IDENTITY="$MIMO_DEVELOPER_ID"
  )
  DMG_IDENTITY="$MIMO_DEVELOPER_ID"
else
  BUILD_ENV+=(
    MUESLI_SKIP_SIGN=1
    MUESLI_ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements"
  )
fi

env "${BUILD_ENV[@]}" "$ROOT/scripts/build_native_app.sh" release
MUESLI_SIGN_IDENTITY="$DMG_IDENTITY" "$ROOT/scripts/create_dmg.sh" "/Applications/Mimo.app" "$OUTPUT_DIR"

echo
echo "Mimo DMG ready in: $OUTPUT_DIR"
if [[ "$DMG_IDENTITY" == "-" ]]; then
  echo "This preview DMG is ad-hoc signed and not notarized. Friends may need to right-click Mimo and choose Open once."
fi
