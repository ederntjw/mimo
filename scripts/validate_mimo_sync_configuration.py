#!/usr/bin/env python3
"""Validate optional account-sync build settings without contacting a server."""

import os
import sys
from urllib.parse import urlsplit


def validate_sync_configuration(project_url: str, publishable_key: str) -> bool:
    """Return whether sync is configured, or reject an incomplete/invalid pair."""
    project_url = project_url.strip()
    publishable_key = publishable_key.strip()
    if not project_url and not publishable_key:
        return False
    if not project_url or not publishable_key:
        raise ValueError(
            "Set both MIMO_SUPABASE_URL and MIMO_SUPABASE_PUBLISHABLE_KEY, "
            "or leave both empty for a local-only library."
        )
    try:
        url = urlsplit(project_url)
        valid = (
            url.scheme.lower() == "https"
            and bool(url.hostname)
            and url.username is None
            and url.password is None
            and not url.query
            and not url.fragment
            and not any(character.isspace() for character in project_url)
        )
        # Accessing port also validates malformed or out-of-range port values.
        _ = url.port
    except ValueError:
        valid = False
    if not valid:
        raise ValueError(
            "MIMO_SUPABASE_URL must be an HTTPS project URL with a host, "
            "without credentials, query parameters, or a fragment."
        )
    return True


def main() -> int:
    try:
        configured = validate_sync_configuration(
            os.environ.get("MIMO_SUPABASE_URL", ""),
            os.environ.get("MIMO_SUPABASE_PUBLISHABLE_KEY", ""),
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    print("Mimo Account sync configuration is complete." if configured else
          "Mimo Account sync is optional and disabled; the library stays on this Mac.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
