#!/usr/bin/env bash
# Optional Apple notarization hook for Railty release builds.
# It is a no-op unless all APPLE_NOTARIZATION_* secrets are set.
set -euo pipefail

APP_PATH="${1:-macos/build/Release/Railty.app}"
ISSUER="${APPLE_NOTARIZATION_ISSUER:-}"
KEY_ID="${APPLE_NOTARIZATION_KEY_ID:-}"
KEY="${APPLE_NOTARIZATION_KEY:-}"

if [[ -z "$ISSUER" || -z "$KEY_ID" || -z "$KEY" ]]; then
  printf 'Apple notarization credentials not configured; skipping notarization.\n'
  exit 0
fi

[[ -d "$APP_PATH" ]] || { printf 'error: app not found: %s\n' "$APP_PATH" >&2; exit 1; }

WORK_DIR="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

printf '%s' "$KEY" > "$WORK_DIR/notarization_key.p8"
/usr/bin/xcrun notarytool store-credentials "railty-notary" \
  --key "$WORK_DIR/notarization_key.p8" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER"

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$WORK_DIR/notarization.zip"
/usr/bin/xcrun notarytool submit "$WORK_DIR/notarization.zip" \
  --keychain-profile "railty-notary" --wait
/usr/bin/xcrun stapler staple "$APP_PATH"
