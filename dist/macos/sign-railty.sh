#!/usr/bin/env bash
# Optional Developer ID signing hook for Railty release builds.
# It is a no-op unless RAILTY_SIGNING_IDENTITY is set.
# Secrets are read from the environment only; nothing is stored in the repo.
set -euo pipefail

APP_PATH="${1:-macos/build/Release/Railty.app}"
IDENTITY="${RAILTY_SIGNING_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  printf 'No RAILTY_SIGNING_IDENTITY configured; keeping the Xcode ad-hoc signature.\n'
  exit 0
fi

[[ -d "$APP_PATH" ]] || { printf 'error: app not found: %s\n' "$APP_PATH" >&2; exit 1; }

WORK_DIR="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

CERT_B64="${RAILTY_SIGNING_CERTIFICATE_B64:-}"
if [[ -n "$CERT_B64" ]]; then
  : "${RAILTY_SIGNING_CERTIFICATE_PASSWORD:?RAILTY_SIGNING_CERTIFICATE_PASSWORD is required with a certificate}"
  : "${RAILTY_KEYCHAIN_PASSWORD:?RAILTY_KEYCHAIN_PASSWORD is required with a certificate}"
  KEYCHAIN="$WORK_DIR/railty-build.keychain-db"

  printf '%s' "$CERT_B64" | /usr/bin/base64 --decode > "$WORK_DIR/certificate.p12"
  /usr/bin/security create-keychain -p "$RAILTY_KEYCHAIN_PASSWORD" "$KEYCHAIN"
  /usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN"
  /usr/bin/security unlock-keychain -p "$RAILTY_KEYCHAIN_PASSWORD" "$KEYCHAIN"
  /usr/bin/security import "$WORK_DIR/certificate.p12" -k "$KEYCHAIN" \
    -P "$RAILTY_SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
  /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$RAILTY_KEYCHAIN_PASSWORD" "$KEYCHAIN"
  export KEYCHAIN_PATH="$KEYCHAIN"
fi

# Sign nested code first (frameworks, XPC services, plug-ins), deepest first.
while IFS= read -r -d '' target; do
  /usr/bin/codesign --verbose -f -s "$IDENTITY" -o runtime --timestamp "$target"
done < <(/usr/bin/python3 - "$APP_PATH" <<'PY'
import os
import sys

app = os.path.abspath(sys.argv[1])
entries = []
for root, dirs, _ in os.walk(os.path.join(app, "Contents")):
    for name in dirs:
        if name.endswith((".framework", ".xpc", ".app", ".plugin")):
            entries.append(os.path.join(root, name))
for path in sorted(entries, key=lambda p: p.count(os.sep), reverse=True):
    sys.stdout.write(path + "\0")
PY
)

ENTITLEMENTS="macos/Ghostty.entitlements"
/usr/bin/codesign --verbose -f -s "$IDENTITY" -o runtime --timestamp \
  --entitlements "$ENTITLEMENTS" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
