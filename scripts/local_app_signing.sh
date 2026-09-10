#!/usr/bin/env bash
# Shared signing policy for the local installer. Sourcing this file has no effects.

mimo_app_developer_id() {
  local signature
  if ! signature="$(codesign -dvvv "$1" 2>&1)"; then
    echo "Cannot inspect the app's signing identity: $1" >&2
    return 1
  fi
  sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' <<< "$signature" | head -n 1
}

mimo_resolve_local_app_signing() {
  local installed_app="$1" requested_identity="$2" needs_build="$3"
  local installed_identity="" identities
  if [[ -d "$installed_app" ]]; then
    installed_identity="$(mimo_app_developer_id "$installed_app")" || return 1
  fi
  if [[ -n "$requested_identity" && "$requested_identity" != - && "$requested_identity" != "Developer ID Application: "* ]]; then
    echo "MIMO_DEVELOPER_ID must name a Developer ID Application identity." >&2
    return 1
  fi
  if [[ -n "$installed_identity" && "$requested_identity" == - ]]; then
    echo "Refusing to replace Mimo's Developer ID signature with ad-hoc signing." >&2
    return 1
  fi

  LOCAL_SIGN_IDENTITY="${requested_identity:-${installed_identity:--}}"
  LOCAL_REQUIRED_DEVELOPER_ID=""
  LOCAL_SIGN_TIMESTAMP=none
  if [[ "$LOCAL_SIGN_IDENTITY" != - ]]; then
    LOCAL_REQUIRED_DEVELOPER_ID="$LOCAL_SIGN_IDENTITY"
    LOCAL_SIGN_TIMESTAMP=--timestamp
    # An already signed staged app needs no local private key to install.
    if [[ "$needs_build" == 1 ]]; then
      if ! identities="$(security find-identity -v -p codesigning)" \
          || ! grep -Fq -- "\"$LOCAL_SIGN_IDENTITY\"" <<< "$identities"; then
        echo "Mimo's Developer ID identity is unavailable. Restore it in Keychain before rebuilding." >&2
        return 1
      fi
    fi
  fi
}

mimo_verify_local_app_signer() {
  [[ -n "$LOCAL_REQUIRED_DEVELOPER_ID" ]] || return 0
  local actual_identity
  actual_identity="$(mimo_app_developer_id "$1")" || return 1
  if [[ "$actual_identity" != "$LOCAL_REQUIRED_DEVELOPER_ID" ]]; then
    echo "The replacement app does not preserve Mimo's Developer ID identity." >&2
    return 1
  fi
}
