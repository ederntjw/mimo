#!/usr/bin/env bash
set -euo pipefail

# Assess the exact distributed artifact without changing Gatekeeper policy.
# Code-signature structure, Sparkle signatures, and release metadata are checked
# by the packaging/update verifier; this gate requires Apple's acceptance and
# an attached ticket so the artifact can be assessed without a network lookup.
usage() {
  echo "usage: scripts/verify_notarized_artifact.sh --app <bundle.app> | --dmg <image.dmg>" >&2
}

if [[ $# != 2 ]]; then
  usage
  exit 2
fi

ARTIFACT="$2"
CHECK_APP_DISTRIBUTION=0
case "$1" in
  --app)
    if [[ ! -d "$ARTIFACT" ]]; then
      echo "ERROR: App bundle not found: $ARTIFACT" >&2
      exit 1
    fi
    ASSESSMENT_ARGS=(-a -vv -t execute)
    CHECK_APP_DISTRIBUTION=1
    ;;
  --dmg)
    if [[ ! -f "$ARTIFACT" ]]; then
      echo "ERROR: DMG not found: $ARTIFACT" >&2
      exit 1
    fi
    ASSESSMENT_ARGS=(-a -vv -t open --context context:primary-signature)
    ;;
  *)
    usage
    exit 2
    ;;
esac

ARTIFACT="$(cd "$(dirname "$ARTIFACT")" && pwd -P)/$(basename "$ARTIFACT")"
if ! ASSESSMENT_OUTPUT="$(LC_ALL=C spctl "${ASSESSMENT_ARGS[@]}" "$ARTIFACT" 2>&1)"; then
  echo "$ASSESSMENT_OUTPUT" >&2
  echo "ERROR: Gatekeeper assessment failed for $ARTIFACT" >&2
  exit 1
fi
printf '%s\n' "$ASSESSMENT_OUTPUT"
# Exit status and an exact acceptance record are both required. Searching for
# the substring 'accepted' would also accept 'not accepted' or an unrelated path.
if ! grep -Fxq -- "$ARTIFACT: accepted" <<< "$ASSESSMENT_OUTPUT" \
    || ! grep -Fxq -- 'source=Notarized Developer ID' <<< "$ASSESSMENT_OUTPUT"; then
  echo "ERROR: Gatekeeper did not confirm Notarized Developer ID acceptance for $ARTIFACT" >&2
  exit 1
fi

if [[ "$CHECK_APP_DISTRIBUTION" == "1" ]]; then
  if ! command -v syspolicy_check >/dev/null 2>&1; then
    echo "ERROR: syspolicy_check is required for app distribution verification on macOS 14 or later." >&2
    exit 1
  fi
  if ! syspolicy_check distribution "$ARTIFACT"; then
    echo "ERROR: App distribution assessment failed for $ARTIFACT" >&2
    exit 1
  fi
fi

if ! xcrun stapler validate "$ARTIFACT"; then
  echo "ERROR: Missing or invalid stapled notarization ticket for $ARTIFACT" >&2
  exit 1
fi

echo "Notarized artifact verified: $ARTIFACT"
