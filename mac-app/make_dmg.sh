#!/usr/bin/env bash
#
# Package Speak.app into a distributable Speak.dmg (drag-to-Applications installer).
#
# Prereq: build the app first with ./build_app.sh
#
# NOTE ON DISTRIBUTION: the app is currently signed with a self-signed dev cert, so
# a DOWNLOADED copy is quarantined by macOS and Gatekeeper will block it
# ("Speak is damaged / from an unidentified developer"). For a smooth public
# download you need an Apple Developer ID cert + notarization (see README). Until
# then, testers open it with: xattr -dr com.apple.quarantine /Applications/Speak.app

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="Speak.app"
DMG="Speak.dmg"
VOL="Speak"

if [[ ! -d "$APP" ]]; then
    echo "No $APP found — run ./build_app.sh first." >&2
    exit 1
fi

echo "==> Staging…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG…"
rm -f "$DMG"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

SIZE="$(du -h "$DMG" | cut -f1)"
echo ""
echo "Built: $HERE/$DMG  ($SIZE)"
echo "Users drag Speak into Applications. If downloaded, they may need to clear"
echo "quarantine until the app is notarized:  xattr -dr com.apple.quarantine /Applications/Speak.app"
