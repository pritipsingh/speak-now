#!/usr/bin/env bash
#
# Build Speak.app from the Swift package.
#
# Command Line Tools are enough — no full Xcode required. This compiles the SPM
# executable and assembles a proper .app bundle (with Info.plist + code signature)
# so macOS can track Microphone and Accessibility permissions.
#
# The SPM target is still named "WisprFlow" (the build product), but the shipped
# app is "Speak" — the binary is renamed on copy and CFBundleExecutable=Speak.
#
# Usage: ./build_app.sh [debug|release]   (default: release)

set -euo pipefail

CONFIG="${1:-release}"
BUILD_PRODUCT="WisprFlow"  # SPM target / compiled binary name
APP_NAME="Speak"           # user-facing app name
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BUILD_PRODUCT"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Build produced no binary at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$HERE/$APP_NAME.app"
echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
rm -rf "$HERE/WisprFlow.app"  # remove the pre-rename bundle if present
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$HERE/Info.plist" "$APP_DIR/Contents/Info.plist"

# Prefer a stable self-signed identity ("WisprFlow Dev") so macOS keeps the
# Microphone/Accessibility grants across rebuilds — its designated requirement is
# tied to the certificate, not the binary hash. Ad-hoc (-) is the fallback, but
# with ad-hoc the hash changes every build and you must re-grant each time.
SIGN_IDENTITY="-"
if security find-identity "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | grep -q "WisprFlow Dev"; then
    SIGN_IDENTITY="WisprFlow Dev"
    echo "==> Code signing (WisprFlow Dev — grants persist)…"
else
    echo "==> Code signing (ad-hoc — grants reset each rebuild; run ./setup_signing.sh once to fix)…"
fi
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1 || {
    echo "   (codesign failed — the app will still run but permissions may reset)"
}

echo ""
echo "Built: $APP_DIR"
echo ""
echo "Run it:            open \"$APP_DIR\""
echo "Or from terminal:  \"$APP_DIR/Contents/MacOS/$APP_NAME\""
echo ""
echo "Look for the mic icon in the menu bar. Hold Right Option and speak."
