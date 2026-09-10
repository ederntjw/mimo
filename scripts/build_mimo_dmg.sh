#!/usr/bin/env bash
set -euo pipefail

# Public/share builds require Developer ID signing and Apple notarization.
# Build away from /Applications and expose the DMG only after its final checks.
#
#   MIMO_DEVELOPER_ID="Developer ID Application: ..." \
#   MUESLI_NOTARY_PROFILE=MimoNotary ./scripts/build_mimo_dmg.sh
#
# An explicitly requested diagnostic preview may use:
#   MIMO_ALLOW_UNNOTARIZED_PREVIEW=1 ./scripts/build_mimo_dmg.sh
# Preview files have a -preview suffix and are unsuitable for public releases.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/localvqe_runtime.sh"
export LC_ALL=C

ALLOW_PREVIEW="${MIMO_ALLOW_UNNOTARIZED_PREVIEW:-0}"
case "$ALLOW_PREVIEW" in 0|1) ;; *) echo "MIMO_ALLOW_UNNOTARIZED_PREVIEW must be 0 or 1." >&2; exit 2 ;; esac
DEFAULT_NOTARIZE=1
[[ "$ALLOW_PREVIEW" == 0 ]] || DEFAULT_NOTARIZE=0
NOTARIZE="${MIMO_NOTARIZE:-$DEFAULT_NOTARIZE}"
case "$NOTARIZE" in 0|1) ;; *) echo "MIMO_NOTARIZE must be 0 or 1." >&2; exit 2 ;; esac
NOTARY_S3_ACCELERATION="${MIMO_NOTARY_S3_ACCELERATION:-1}"
case "$NOTARY_S3_ACCELERATION" in 0|1) ;; *) echo "MIMO_NOTARY_S3_ACCELERATION must be 0 or 1." >&2; exit 2 ;; esac
if [[ "$NOTARIZE" == 0 && "$ALLOW_PREVIEW" != 1 ]]; then
  echo "ERROR: Public/share builds require notarization. Diagnostic previews require MIMO_ALLOW_UNNOTARIZED_PREVIEW=1." >&2
  exit 2
fi

DMG_IDENTITY="${MIMO_DEVELOPER_ID:--}"
if [[ "$NOTARIZE" == 1 && "$DMG_IDENTITY" != "Developer ID Application: "* ]]; then
  echo "ERROR: A notarized release requires MIMO_DEVELOPER_ID naming a Developer ID Application identity." >&2
  exit 2
fi
if [[ "$DMG_IDENTITY" != - ]]; then
  if [[ "$DMG_IDENTITY" != "Developer ID Application: "* ]]; then
    echo "ERROR: MIMO_DEVELOPER_ID must name a Developer ID Application identity." >&2
    exit 2
  fi
  if ! security find-identity -v -p codesigning | grep -Fq -- "\"$DMG_IDENTITY\""; then
    echo "ERROR: The requested Developer ID Application identity is not available in the keychain." >&2
    exit 2
  fi
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: Mimo distribution builds require Xcode and xcodegen for App Intents metadata." >&2
  exit 2
fi

DEFAULT_OUTPUT_DIR="$ROOT/dist-share"
[[ "$NOTARIZE" == 1 ]] || DEFAULT_OUTPUT_DIR="$ROOT/dist-share-preview"
OUTPUT_DIR="${MIMO_DMG_OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
SPARKLE_FEED_URL="${MIMO_SPARKLE_FEED_URL:-https://github.com/ederntjw/mimo/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${MIMO_SPARKLE_PUBLIC_KEY:-5YCc2MtI+BSleheL65Le6rsFk6Ynw+k+19/KOcc60BY=}"
NOTARY_PROFILE="${MUESLI_NOTARY_PROFILE:-MimoNotary}"
PACKAGE_WORK_ROOT="${MIMO_PACKAGE_WORK_ROOT:-${TMPDIR:-/tmp}}"
if [[ "$PACKAGE_WORK_ROOT" != /* ]]; then
  echo "ERROR: MIMO_PACKAGE_WORK_ROOT must be an absolute directory path." >&2
  exit 2
fi
WORK_DIR=""
MOUNT_POINT=""
OUTPUT_TEMP_DMG=""
RETAIN_NOTARY_WORK=0
NOTARY_PHASE_DIR=""
NOTARY_SUBMISSION_ID=""
NOTARY_UPLOAD_COMPLETED=0
cleanup() {
  [[ -z "$OUTPUT_TEMP_DMG" ]] || rm -f "$OUTPUT_TEMP_DMG"
  if [[ -n "$MOUNT_POINT" ]]; then
    if ! hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null; then
      echo "Could not detach $MOUNT_POINT; packaging staging retained at $WORK_DIR." >&2
      return
    fi
  fi
  if [[ "$RETAIN_NOTARY_WORK" == 1 ]]; then
    # A signal may arrive before submit returns control to notarize_artifact.
    if [[ -z "$NOTARY_SUBMISSION_ID" && -f "$NOTARY_PHASE_DIR/submit.json" ]]; then
      NOTARY_SUBMISSION_ID="$(read_notary_submission_id "$NOTARY_PHASE_DIR/submit.json" 2>/dev/null)" || true
    fi
    echo "Packaging stopped; the exact signed artifacts and notarization receipts are retained at $WORK_DIR." >&2
    echo "This run did not expose a final DMG. Review $NOTARY_PHASE_DIR before attempting another upload." >&2
    if [[ -n "$NOTARY_SUBMISSION_ID" ]]; then
      printf '%s\n' "$NOTARY_SUBMISSION_ID" > "$NOTARY_PHASE_DIR/submission-id.txt"
      echo "Known submission: $NOTARY_SUBMISSION_ID" >&2
      printf 'Inspect it: xcrun notarytool info %q --keychain-profile %q\n' "$NOTARY_SUBMISSION_ID" "$NOTARY_PROFILE" >&2
      if [[ "$NOTARY_UPLOAD_COMPLETED" == 1 ]]; then
        printf 'If it is still In Progress, continue waiting without resubmitting: xcrun notarytool wait %q --keychain-profile %q --timeout 20m\n' "$NOTARY_SUBMISSION_ID" "$NOTARY_PROFILE" >&2
      else
        echo "Upload completion was not confirmed. A submission ID or In Progress status alone does not prove that Apple received the full file." >&2
      fi
      printf 'Retrieve the completed submission log: xcrun notarytool log %q --keychain-profile %q\n' "$NOTARY_SUBMISSION_ID" "$NOTARY_PROFILE" >&2
    else
      echo "No submission ID was recovered. Check the retained submit output and Apple submission history; do not blindly resubmit an uncertain request." >&2
    fi
    echo "Acceptance still requires stapling and all distribution checks before a release can be shared." >&2
    return
  fi
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
# Signing must run outside a cloud-synced output directory: File Provider can
# reattach FinderInfo to nested bundles after build_native_app clears xattrs.
mkdir -p "$PACKAGE_WORK_ROOT"
PACKAGE_WORK_ROOT="$(cd "$PACKAGE_WORK_ROOT" && pwd)"
WORK_DIR="$(mktemp -d "$PACKAGE_WORK_ROOT/.mimo-package.XXXXXX")"
APP_PATH="$WORK_DIR/install-root/Mimo.app"

read_notary_submission_id() {
  python3 - "$1" <<'PY'
import json, sys, uuid
try:
    with open(sys.argv[1]) as source:
        result = json.load(source)
    print(str(uuid.UUID(result["id"])))
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    raise SystemExit("ERROR: Could not recover a valid submission ID from Apple's response.")
PY
}

fetch_notary_log() {
  # A pending request may not have a log yet. Preserve that response too, without
  # turning a diagnostic request into a replacement submission.
  local result=0
  xcrun notarytool log "$NOTARY_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" \
    > "$NOTARY_PHASE_DIR/log.json" 2> "$NOTARY_PHASE_DIR/log.stderr.log" || result=$?
  printf '%s\n' "$result" > "$NOTARY_PHASE_DIR/log.exit-code"
}

notarize_artifact() {
  local artifact="$1" label="$2" phase="$3" route="--s3-acceleration" result=0
  RETAIN_NOTARY_WORK=1
  NOTARY_PHASE_DIR="$WORK_DIR/notarization/$phase"
  NOTARY_SUBMISSION_ID=""
  NOTARY_UPLOAD_COMPLETED=0
  mkdir -p "$NOTARY_PHASE_DIR"
  python3 - "$artifact" > "$NOTARY_PHASE_DIR/artifact.json" <<'PY'
import hashlib, json, sys
digest = hashlib.sha256()
with open(sys.argv[1], "rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
json.dump({"path": sys.argv[1], "sha256": digest.hexdigest()}, sys.stdout)
sys.stdout.write("\n")
PY
  [[ "$NOTARY_S3_ACCELERATION" == 1 ]] || route="--no-s3-acceleration"
  printf '%s\n' "$route" > "$NOTARY_PHASE_DIR/upload-route.txt"
  echo "Submitting $label to Apple notarization..."
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" \
    --no-wait "$route" --output-format json \
    > "$NOTARY_PHASE_DIR/submit.json" 2> "$NOTARY_PHASE_DIR/submit.stderr.log" || result=$?
  printf '%s\n' "$result" > "$NOTARY_PHASE_DIR/submit.exit-code"
  if [[ "$result" != 0 ]]; then
    NOTARY_SUBMISSION_ID="$(read_notary_submission_id "$NOTARY_PHASE_DIR/submit.json" 2>/dev/null)" || true
    echo "ERROR: Apple notarization upload failed or was interrupted for $label; see the retained submit receipts." >&2
    return 1
  fi
  NOTARY_UPLOAD_COMPLETED=1
  printf 'Upload command completed successfully.\n' > "$NOTARY_PHASE_DIR/upload-completed.txt"
  NOTARY_SUBMISSION_ID="$(read_notary_submission_id "$NOTARY_PHASE_DIR/submit.json")" || return 1
  printf '%s\n' "$NOTARY_SUBMISSION_ID" > "$NOTARY_PHASE_DIR/submission-id.txt"
  echo "Apple upload completed for $label; submission $NOTARY_SUBMISSION_ID. Waiting up to 20 minutes..."
  xcrun notarytool wait "$NOTARY_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" \
    --timeout 20m --output-format json \
    > "$NOTARY_PHASE_DIR/wait.json" 2> "$NOTARY_PHASE_DIR/wait.stderr.log" || result=$?
  printf '%s\n' "$result" > "$NOTARY_PHASE_DIR/wait.exit-code"
  fetch_notary_log
  if [[ "$result" != 0 ]]; then
    echo "ERROR: Waiting for Apple did not complete for $label. The existing submission may still be processing; no new upload was attempted." >&2
    return 1
  fi
  python3 - "$NOTARY_PHASE_DIR/wait.json" "$label" "$NOTARY_SUBMISSION_ID" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    result = json.load(source)
if result.get("id") != sys.argv[3]:
    raise SystemExit("ERROR: Apple's result does not match the submitted artifact's ID.")
if result.get("status") != "Accepted":
    raise SystemExit(f"ERROR: Apple did not accept {sys.argv[2]} (status: {result.get('status', 'missing')}, submission: {result.get('id', 'missing')}).")
print(f"Apple accepted {sys.argv[2]}.")
PY
}

verify_signature() {
  local artifact="$1" kind="$2" details
  if [[ "$kind" == app ]]; then
    codesign --verify --deep --strict --verbose=2 "$artifact"
  else
    codesign --verify --strict --verbose=2 "$artifact"
  fi
  details="$(codesign -dvvv "$artifact" 2>&1)"
  if [[ "$kind" == app ]] && ! grep -q 'flags=.*runtime' <<< "$details"; then
    echo "ERROR: App is missing hardened runtime." >&2
    return 1
  fi
  if [[ "$NOTARIZE" == 1 ]] && ! grep -Fxq -- "Authority=$DMG_IDENTITY" <<< "$details"; then
    echo "ERROR: $kind is not signed with the requested Developer ID Application identity." >&2
    return 1
  fi
}

verify_notarized() {
  "$ROOT/scripts/verify_notarized_artifact.sh" "--$2" "$1"
}

LOCALVQE_LIB_DIR="${MUESLI_LOCALVQE_LIB_DIR:-$ROOT/native/MuesliNative/LocalVQE/lib}"
if ! muesli_localvqe_runtime_is_complete "$LOCALVQE_LIB_DIR"; then
  if [[ -n "${MUESLI_LOCALVQE_LIB_DIR:-}" ]]; then
    echo "ERROR: The explicitly selected LocalVQE runtime is incomplete." >&2
    exit 1
  fi
  "$ROOT/scripts/build_localvqe.sh"
fi

BUILD_ENV=(
  MUESLI_APP_NAME=Mimo
  MUESLI_DISPLAY_NAME=Mimo
  MUESLI_APP_BUNDLE_NAME=Mimo.app
  MUESLI_EXECUTABLE_NAME=Mimo
  MUESLI_SUPPORT_DIR_NAME=Mimo
  MUESLI_BUNDLE_ID=com.muesli.app
  MUESLI_INSTALL_DIR="$WORK_DIR/install-root"
  MUESLI_SPARKLE_FEED_URL="$SPARKLE_FEED_URL"
  MUESLI_SPARKLE_EDKEY="$SPARKLE_PUBLIC_KEY"
  MUESLI_USE_XCODE_BUILD=1
  MUESLI_SKIP_SIGN=0
  MUESLI_SIGN_IDENTITY="$DMG_IDENTITY"
  MUESLI_CODESIGN_TIMESTAMP=--timestamp
  MUESLI_REQUIRE_LOCALVQE=1
  MUESLI_ALLOW_MISSING_LOCALVQE=0
)
if [[ -z "${MUESLI_PROVISIONING_PROFILE:-}" ]]; then
  BUILD_ENV+=(
    MUESLI_ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements"
    MUESLI_PROVISIONING_PROFILE=
    MUESLI_APS_ENVIRONMENT=
    MUESLI_ICLOUD_CONTAINER_ENVIRONMENT=
  )
fi
if [[ "$DMG_IDENTITY" == - ]]; then
  BUILD_ENV+=(MUESLI_CODESIGN_TIMESTAMP=none)
fi
env "${BUILD_ENV[@]}" "$ROOT/scripts/build_native_app.sh" release

verify_signature "$APP_PATH" app
muesli_localvqe_runtime_is_complete "$APP_PATH/Contents/MacOS"
if [[ ! -s "$APP_PATH/Contents/Resources/Models/localvqe/localvqe-v1.2-1.3M-f32.gguf" ]]; then
  echo "ERROR: Packaged LocalVQE model is missing or empty." >&2
  exit 1
fi
if [[ ! -s "$APP_PATH/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]; then
  echo "ERROR: Packaged App Intents metadata is missing or empty." >&2
  exit 1
fi
VERSION="$(python3 - "$APP_PATH/Contents/Info.plist" <<'PY'
import plistlib, re, sys
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
if info.get("CFBundleIdentifier") != "com.muesli.app" or info.get("MuesliSupportDirectoryName") != "Mimo":
    raise SystemExit("ERROR: Built app has an unexpected app/data identity.")
version = info.get("CFBundleShortVersionString", "")
if not re.fullmatch(r"[0-9][0-9A-Za-z.\-]*", version):
    raise SystemExit("ERROR: Built app has an invalid version.")
print(version)
PY
)"
FINAL_NAME="Mimo-$VERSION.dmg"
[[ "$NOTARIZE" == 1 ]] || FINAL_NAME="Mimo-$VERSION-preview.dmg"
FINAL_DMG_PATH="$OUTPUT_DIR/$FINAL_NAME"
if [[ -e "$FINAL_DMG_PATH" || -L "$FINAL_DMG_PATH" ]]; then
  echo "ERROR: Refusing to replace an existing artifact: $FINAL_DMG_PATH" >&2
  exit 1
fi

if [[ "$NOTARIZE" == 1 ]]; then
  APP_ZIP="$WORK_DIR/Mimo.app.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP"
  notarize_artifact "$APP_ZIP" Mimo.app app
  xcrun stapler staple "$APP_PATH"
  verify_signature "$APP_PATH" app
  verify_notarized "$APP_PATH" app
fi

MUESLI_SIGN_IDENTITY="$DMG_IDENTITY" "$ROOT/scripts/create_dmg.sh" "$APP_PATH" "$WORK_DIR/dmg"
DMG_PATH="$WORK_DIR/dmg/Mimo-$VERSION.dmg"
[[ -f "$DMG_PATH" ]]
verify_signature "$DMG_PATH" dmg
if [[ "$NOTARIZE" == 1 ]]; then
  notarize_artifact "$DMG_PATH" "$(basename "$DMG_PATH")" dmg
  xcrun stapler staple "$DMG_PATH"
  verify_signature "$DMG_PATH" dmg
  verify_notarized "$DMG_PATH" dmg

  # Verify the exact app inside the final image, including the copied staple.
  MOUNT_POINT="$WORK_DIR/mounted"
  mkdir "$MOUNT_POINT"
  hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" -quiet
  verify_signature "$MOUNT_POINT/Mimo.app" app
  verify_notarized "$MOUNT_POINT/Mimo.app" app
  hdiutil detach "$MOUNT_POINT" -quiet
  MOUNT_POINT=""
fi

# Copy only the finished DMG into the output filesystem. Verify those bytes
# before an atomic same-filesystem link; work/output may be on different disks.
OUTPUT_TEMP_DMG="$(mktemp "$OUTPUT_DIR/.mimo-delivery.XXXXXX")"
cp "$DMG_PATH" "$OUTPUT_TEMP_DMG"
if ! cmp -s "$DMG_PATH" "$OUTPUT_TEMP_DMG"; then
  echo "ERROR: The delivery copy does not match the verified DMG." >&2
  exit 1
fi
# This refuses to overwrite an artifact created during notarization or copying.
ln "$OUTPUT_TEMP_DMG" "$FINAL_DMG_PATH"
RETAIN_NOTARY_WORK=0
echo "Mimo DMG ready: $FINAL_DMG_PATH"
if [[ "$NOTARIZE" == 1 ]]; then
  echo "Developer ID signatures, Apple notarization, stapled tickets, and Gatekeeper acceptance verified."
else
  echo "Diagnostic preview only: this DMG is not notarized and may be blocked by Gatekeeper."
fi
