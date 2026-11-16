#!/usr/bin/env bash
# Verify a built Railty.app and package it for GitHub Releases.
# Usage: package-railty.sh <app-path> <version> <output-zip> <arch|universal>
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

APP_PATH="${1:-macos/build/Release/Railty.app}"
VERSION="${2:-}"
OUTPUT_ZIP="${3:-Railty-macos-arm64.zip}"
EXPECTED_ARCH="${4:-arm64}"

[[ -n "$VERSION" ]] || die "version is required"
VERSION_NO_V="${VERSION#v}"

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null ||
    die "missing Info.plist key: $2"
}

[[ -d "$APP_PATH" ]] || die "app bundle not found: $APP_PATH"
[[ "$(basename "$APP_PATH")" == "Railty.app" ]] ||
  die "app bundle must be named Railty.app, got: $(basename "$APP_PATH")"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"

BUNDLE_ID="$(plist_get "$INFO_PLIST" CFBundleIdentifier)"
[[ "$BUNDLE_ID" == "com.vendettar.railty" ]] ||
  die "unexpected CFBundleIdentifier: $BUNDLE_ID"

APP_VERSION="$(plist_get "$INFO_PLIST" CFBundleShortVersionString)"
[[ "$APP_VERSION" == "$VERSION_NO_V" ]] ||
  die "CFBundleShortVersionString is $APP_VERSION, expected $VERSION_NO_V"

EXECUTABLE="$(plist_get "$INFO_PLIST" CFBundleExecutable)"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
[[ -x "$EXECUTABLE_PATH" ]] || die "executable not found: $EXECUTABLE_PATH"

ACTUAL_ARCHS="$(lipo -archs "$EXECUTABLE_PATH" | tr ' ' '\n' | grep -v '^$' | sort | paste -s -d, -)"
case "$EXPECTED_ARCH" in
  arm64)
    [[ "$ACTUAL_ARCHS" == "arm64" ]] ||
      die "expected an arm64-only executable, got: $ACTUAL_ARCHS"
    ;;
  x86_64)
    [[ "$ACTUAL_ARCHS" == "x86_64" ]] ||
      die "expected an x86_64-only executable, got: $ACTUAL_ARCHS"
    ;;
  universal)
    [[ "$ACTUAL_ARCHS" == "arm64,x86_64" ]] ||
      die "expected arm64 + x86_64, got: $ACTUAL_ARCHS"
    ;;
  *) die "unknown expected architecture: $EXPECTED_ARCH" ;;
esac

printf 'Verified %s: bundle id=%s version=%s archs=%s\n' \
  "$APP_PATH" "$BUNDLE_ID" "$APP_VERSION" "$ACTUAL_ARCHS"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
  printf 'warning: signature verification failed (expected for unsigned/ad-hoc test builds)\n' >&2
fi

rm -f "$OUTPUT_ZIP" "$OUTPUT_ZIP.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_ZIP"
SHA256="$(/usr/bin/shasum -a 256 "$OUTPUT_ZIP" | /usr/bin/awk '{print $1}')"
printf '%s\n' "$SHA256" > "$OUTPUT_ZIP.sha256"

printf 'zip=%s\nsha256=%s\n' "$OUTPUT_ZIP" "$SHA256"
