#!/usr/bin/env bash
# Sign a Railty release build. With RAILTY_SIGNING_IDENTITY this applies a
# Developer ID signature; otherwise it re-signs everything ad-hoc so the
# bundled Sparkle framework and the app share a consistent signature.
# Secrets are read from the environment only; nothing is stored in the repo.
set -euo pipefail

APP_PATH="${1:-macos/build/Release/Railty.app}"
IDENTITY="${RAILTY_SIGNING_IDENTITY:-}"
ADHOC=false

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  ADHOC=true
  printf 'No RAILTY_SIGNING_IDENTITY configured; using a consistent ad-hoc signature.\n'
fi

[[ -d "$APP_PATH" ]] || { printf 'error: app not found: %s\n' "$APP_PATH" >&2; exit 1; }

WORK_DIR="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

CERT_B64="${RAILTY_SIGNING_CERTIFICATE_B64:-}"
if [[ "$ADHOC" == "false" && -n "$CERT_B64" ]]; then
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

# Sign nested code first (frameworks, XPC services, plug-ins, versioned binaries),
# deepest first. Ad-hoc builds omit the hardened-runtime flag: without a stable
# Team ID, library validation rejects the separately built Sparkle framework.
while IFS= read -r -d '' target; do
  if [[ "$ADHOC" == "true" ]]; then
    /usr/bin/codesign -f -s "$IDENTITY" \
      --preserve-metadata=entitlements,identifier "$target" >/dev/null 2>&1
  else
    /usr/bin/codesign --verbose -f -s "$IDENTITY" -o runtime --timestamp "$target"
  fi
done < <(/usr/bin/python3 - "$APP_PATH" <<'PY'
import os
import sys

app = os.path.abspath(sys.argv[1])
entries = []
for root, dirs, files in os.walk(os.path.join(app, "Contents")):
    for name in dirs:
        if name.endswith((".framework", ".xpc", ".app", ".plugin")):
            path = os.path.join(root, name)
            entries.append(path)
            if name.endswith(".framework"):
                versions = os.path.join(path, "Versions")
                if os.path.isdir(versions):
                    binary = name[: -len(".framework")]
                    for version in os.listdir(versions):
                        candidate = os.path.join(versions, version, binary)
                        if os.path.isfile(candidate):
                            entries.append(candidate)
for path in sorted(set(entries), key=lambda p: p.count(os.sep), reverse=True):
    sys.stdout.write(path + "\0")
PY
)

ENTITLEMENTS="macos/Railty.entitlements"
if [[ "$ADHOC" == "true" ]]; then
  /usr/bin/codesign --verbose -f -s "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" "$APP_PATH"
else
  /usr/bin/codesign --verbose -f -s "$IDENTITY" -o runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$APP_PATH"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
