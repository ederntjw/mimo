#!/usr/bin/env bash
set -euo pipefail

# Maintain one release-optimized Mimo app with a stable signing identity. Build and verify
# away from /Applications before touching the installed app or quitting it.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Build and replace /Applications/Mimo.app, preserving its identity and data.

Usage: ./scripts/install_local_app.sh [options]

  --stage-only        Build and verify; leave the installed app running and unchanged.
  --install-staged PATH
                      Verify and install an already built Mimo.app at an absolute
                      path, without rebuilding. May combine with options below.
  --remove-dev-lanes  Archive and remove installed MuesliDevA/B/C app bundles.
                      Their settings, meeting data, and model caches are preserved.
  --launch            Launch Mimo after a successful installation.
  --help              Show this help.

Builds Release through Xcode and includes App Intents and LocalVQE. Reuses the
installed Developer ID identity, or MIMO_DEVELOPER_ID when explicitly set.
Before Developer ID is configured, uses local ad-hoc signing. Keeps com.muesli.app
and the Mimo support directory stable across replacements.
This does not create a notarized distribution or publish a release.
Existing Sparkle feed and verification key are preserved unless explicitly
overridden with MUESLI_SPARKLE_FEED_URL / MUESLI_SPARKLE_EDKEY.
Prior app bundles are stored as ZIP archives in ~/Library/Application Support/
Mimo Backups/Apps. App data is never reset, merged, or removed.
EOF
}

STAGE_ONLY=0
STAGED_INPUT=""
REMOVE_DEV_LANES=0
LAUNCH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage-only) STAGE_ONLY=1 ;;
    --install-staged)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--install-staged requires an absolute app path." >&2; exit 2; }
      STAGED_INPUT="$2"
      shift
      ;;
    --remove-dev-lanes) REMOVE_DEV_LANES=1 ;;
    --launch) LAUNCH=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
if [[ "$STAGE_ONLY" -eq 1 && ( "$REMOVE_DEV_LANES" -eq 1 || "$LAUNCH" -eq 1 || -n "$STAGED_INPUT" ) ]]; then
  echo "--stage-only cannot be combined with --install-staged, --remove-dev-lanes, or --launch." >&2
  exit 2
fi
if [[ -n "$STAGED_INPUT" && "$STAGED_INPUT" != /* ]]; then
  echo "--install-staged requires an absolute app path." >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This installer requires macOS with Xcode and xcodegen." >&2
  exit 1
fi
if [[ "$STAGE_ONLY" -eq 0 && ! -w /Applications ]]; then
  echo "The current user cannot replace apps in /Applications." >&2
  exit 1
fi

source "$ROOT/scripts/muesli_spm_cache.sh"
source "$ROOT/scripts/localvqe_runtime.sh"
source "$ROOT/scripts/local_app_signing.sh"
APP_PATH="/Applications/Mimo.app"
BACKUP_ROOT="$HOME/Library/Application Support/Mimo Backups/Apps"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LOCK_DIR="$HOME/Library/Caches/muesli-local-install.lock"
RUN_DIR=""
PREPARED_ROOT="/Applications/.mimo-install-$STAMP"
PREPARED_APP="$PREPARED_ROOT/Mimo.app"
PREVIOUS_APP="/Applications/.mimo-previous-$STAMP"
OLD_APP_MOVED=0
NEW_APP_INSTALLED=0
INSTALL_COMPLETE=0

read_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

assert_app_identity() {
  local app="$1" expected_id="$2"
  if [[ -L "$app" || ! -d "$app" || "$(read_plist_value "$app" CFBundleIdentifier)" != "$expected_id" ]]; then
    echo "Refusing to replace an unexpected app or symbolic link: $app" >&2
    return 1
  fi
}

if [[ -n "$STAGED_INPUT" ]]; then
  assert_app_identity "$STAGED_INPUT" com.muesli.app
fi

if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
  assert_app_identity "$APP_PATH" com.muesli.app
  if [[ "$(read_plist_value "$APP_PATH" MuesliSupportDirectoryName)" != Mimo ]]; then
    echo "The installed app does not use the Mimo support directory; refusing to change its data identity." >&2
    exit 1
  fi
fi

# Do not fall back to the upstream Muesli feed when rebuilding this local fork.
if [[ "${MUESLI_SPARKLE_FEED_URL+x}" == x ]]; then
  FEED_URL="$MUESLI_SPARKLE_FEED_URL"
elif [[ -d "$APP_PATH" ]]; then
  FEED_URL="$(read_plist_value "$APP_PATH" SUFeedURL)"
elif [[ -n "$STAGED_INPUT" ]]; then
  FEED_URL="$(read_plist_value "$STAGED_INPUT" SUFeedURL)"
else
  FEED_URL="https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml"
fi
if [[ "${MUESLI_SPARKLE_EDKEY+x}" == x ]]; then
  FEED_KEY="$MUESLI_SPARKLE_EDKEY"
elif [[ -d "$APP_PATH" ]]; then
  FEED_KEY="$(read_plist_value "$APP_PATH" SUPublicEDKey)"
elif [[ -n "$STAGED_INPUT" ]]; then
  FEED_KEY="$(read_plist_value "$STAGED_INPUT" SUPublicEDKey)"
else
  FEED_KEY=""
fi
if [[ -n "$FEED_URL" && -z "$FEED_KEY" ]]; then
  echo "No update verification key is available. Set MUESLI_SPARKLE_EDKEY, or set MUESLI_SPARKLE_FEED_URL='' to disable updates." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOCK_DIR")"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another local install may be running. If it exited, remove the stale lock: $LOCK_DIR" >&2
  exit 1
fi
cleanup() {
  local status=$?
  if [[ "$INSTALL_COMPLETE" -eq 0 ]]; then
    if [[ "$NEW_APP_INSTALLED" -eq 1 ]]; then
      rm -rf "$APP_PATH"
    fi
    if [[ "$OLD_APP_MOVED" -eq 1 && -d "$PREVIOUS_APP" ]]; then
      mv "$PREVIOUS_APP" "$APP_PATH" || echo "Restore the previous app from $PREVIOUS_APP" >&2
    fi
  fi
  [[ ! -e "$PREPARED_ROOT" ]] || rm -rf "$PREPARED_ROOT"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if [[ "$status" -ne 0 && -n "$RUN_DIR" ]]; then
    echo "Build staging retained for inspection: $RUN_DIR" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mimo-local-install.XXXXXX")"
STAGED_APP="${STAGED_INPUT:-$RUN_DIR/install-root/Mimo.app}"
mimo_resolve_local_app_signing "$APP_PATH" "${MIMO_DEVELOPER_ID:-}" "$([[ -z "$STAGED_INPUT" ]] && echo 1 || echo 0)"
if [[ -z "$STAGED_INPUT" ]]; then
SCRATCH_PATH="$(muesli_resolve_spm_scratch_path "$(muesli_worktree_spm_scratch_channel local-app-release "$ROOT")")"
LOCALVQE_LIB_DIR="${MUESLI_LOCALVQE_LIB_DIR:-$ROOT/native/MuesliNative/LocalVQE/lib}"
if ! muesli_localvqe_runtime_is_complete "$LOCALVQE_LIB_DIR"; then
  if [[ -n "${MUESLI_LOCALVQE_LIB_DIR:-}" ]]; then
    echo "The explicitly selected LocalVQE runtime is incomplete: $LOCALVQE_LIB_DIR" >&2
    exit 1
  fi
  "$ROOT/scripts/build_localvqe.sh"
fi

env \
  MUESLI_APP_NAME=Mimo \
  MUESLI_DISPLAY_NAME=Mimo \
  MUESLI_APP_BUNDLE_NAME=Mimo.app \
  MUESLI_EXECUTABLE_NAME=Mimo \
  MUESLI_BUNDLE_ID=com.muesli.app \
  MUESLI_SUPPORT_DIR_NAME=Mimo \
  MUESLI_INSTALL_DIR="$RUN_DIR/install-root" \
  MUESLI_USE_XCODE_BUILD=1 \
  MUESLI_SWIFTPM_SCRATCH_PATH="$SCRATCH_PATH" \
  MUESLI_XCODEBUILD_DERIVED_DATA="${MUESLI_XCODEBUILD_DERIVED_DATA:-$SCRATCH_PATH/xcodebuild}" \
  MUESLI_SIGN_IDENTITY="$LOCAL_SIGN_IDENTITY" \
  MUESLI_SKIP_SIGN=0 \
  MUESLI_CODESIGN_TIMESTAMP="$LOCAL_SIGN_TIMESTAMP" \
  MUESLI_ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements" \
  MUESLI_PROVISIONING_PROFILE= \
  MUESLI_APS_ENVIRONMENT= \
  MUESLI_ICLOUD_CONTAINER_ENVIRONMENT= \
  MUESLI_REQUIRE_LOCALVQE=1 \
  MUESLI_ALLOW_MISSING_LOCALVQE=0 \
  MUESLI_TELEMETRY_CHANNEL=unconfigured \
  MUESLI_TELEMETRYDECK_APP_ID= \
  MUESLI_SPARKLE_FEED_URL="$FEED_URL" \
  MUESLI_SPARKLE_EDKEY="$FEED_KEY" \
  "$ROOT/scripts/build_native_app.sh" release
fi

verify_app() {
  local app="$1"
  assert_app_identity "$app" com.muesli.app
  [[ "$(read_plist_value "$app" MuesliSupportDirectoryName)" == Mimo ]]
  [[ "$(read_plist_value "$app" SUFeedURL)" == "$FEED_URL" ]]
  [[ "$(read_plist_value "$app" SUPublicEDKey)" == "$FEED_KEY" ]]
  codesign --verify --deep --strict "$app"
  mimo_verify_local_app_signer "$app"
  [[ -x "$app/Contents/MacOS/Mimo" ]]
  [[ -s "$app/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]
  muesli_localvqe_runtime_is_complete "$app/Contents/MacOS"
  [[ -s "$app/Contents/Resources/Models/localvqe/localvqe-v1.2-1.3M-f32.gguf" ]]
  "$app/Contents/MacOS/muesli-cli" spec > "$RUN_DIR/cli-spec.json"
  "$app/Contents/MacOS/muesli-cli" transcribe --help > "$RUN_DIR/cli-transcribe-help.txt"
  /usr/bin/grep -q '"command" : "muesli-cli spec"' "$RUN_DIR/cli-spec.json"
  /usr/bin/grep -q 'USAGE: muesli-cli transcribe' "$RUN_DIR/cli-transcribe-help.txt"
}

verify_app "$STAGED_APP"
if [[ "$STAGE_ONLY" -eq 1 ]]; then
  echo "Validated app ready for inspection: $STAGED_APP"
  exit 0
fi

quit_app() {
  # NSRunningApplication uses the normal app lifecycle without scripting the
  # app or requesting Apple Events automation permission. Never force quit.
  /usr/bin/swift - "$1" <<'SWIFT'
import AppKit
import Foundation

let requestedURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let applications = NSWorkspace.shared.runningApplications.filter {
    $0.bundleURL?.standardizedFileURL.path == requestedURL.path
}
for application in applications {
    print("Requesting a normal quit: \(requestedURL.path)")
    guard application.terminate() else {
        fputs("The app declined to quit; installation stopped without forcing it.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(30)
while applications.contains(where: { !$0.isTerminated }) {
    guard Date() < deadline else {
        fputs("The app is still running; installation stopped without forcing it.\n", stderr)
        exit(1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
SWIFT
}

archive_app() {
  local app="$1" archive="$BACKUP_ROOT/$STAMP-$(basename "$1").zip"
  (umask 077; mkdir -p "$BACKUP_ROOT"; /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive")
  /usr/bin/unzip -tq "$archive" >/dev/null
  echo "Previous app archived: $archive"
}

# Copy and verify on the destination volume before the short replacement step.
mkdir "$PREPARED_ROOT"
/usr/bin/ditto "$STAGED_APP" "$PREPARED_APP"
verify_app "$PREPARED_APP"
quit_app "$APP_PATH"
if [[ -d "$APP_PATH" ]]; then
  assert_app_identity "$APP_PATH" com.muesli.app
  archive_app "$APP_PATH"
  OLD_APP_MOVED=1
  mv "$APP_PATH" "$PREVIOUS_APP"
fi
NEW_APP_INSTALLED=1
mv "$PREPARED_APP" "$APP_PATH"
verify_app "$APP_PATH"
INSTALL_COMPLETE=1
if [[ "$OLD_APP_MOVED" -eq 1 ]]; then rm -rf "$PREVIOUS_APP"; fi

if [[ "$REMOVE_DEV_LANES" -eq 1 ]]; then
  for lane in A B C; do
    lane_app="/Applications/MuesliDev$lane.app"
    [[ -e "$lane_app" || -L "$lane_app" ]] || continue
    lane_lower="$(printf '%s' "$lane" | tr '[:upper:]' '[:lower:]')"
    assert_app_identity "$lane_app" "com.muesli.dev.$lane_lower"
    quit_app "$lane_app"
    archive_app "$lane_app"
    rm -rf "$lane_app"
  done
fi

rm -rf "$RUN_DIR"
echo "Installed and verified: $APP_PATH"
echo "Settings, meetings, recordings, authentication, and model caches were preserved."
if [[ "$LAUNCH" -eq 1 ]]; then /usr/bin/open -a "$APP_PATH"; fi
