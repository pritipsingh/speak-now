#!/usr/bin/env bash
#
# Create a stable, self-signed "WisprFlow Dev" code-signing identity in your login
# keychain. Signing WisprFlow.app with this identity keeps its Accessibility and
# Microphone grants across rebuilds (unlike ad-hoc signing, where the binary hash
# changes every build and macOS makes you re-grant).
#
# Run once. Safe to re-run — it no-ops if the identity already exists.
# The certificate is self-signed and used only locally; it is NOT trusted for
# distribution (that's fine for a dev tool on your own machine).

set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity "$KEYCHAIN" 2>/dev/null | grep -q "WisprFlow Dev"; then
    echo "Identity 'WisprFlow Dev' already present — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=WisprFlow Dev/O=Agno Dev" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

# -legacy is required so macOS's `security` can read the PKCS#12 (OpenSSL 3 default
# algorithms are rejected with a MAC verification error otherwise).
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" \
    -passout pass:wispr -name "WisprFlow Dev" -legacy -macalg sha1 >/dev/null 2>&1

echo "==> Importing into login keychain (allowing codesign to use it)…"
security import "$TMP/dev.p12" -k "$KEYCHAIN" -P "wispr" -T /usr/bin/codesign -A >/dev/null

if security find-identity "$KEYCHAIN" 2>/dev/null | grep -q "WisprFlow Dev"; then
    echo "Done. 'WisprFlow Dev' identity installed."
    echo "Rebuild with ./build_app.sh and grant Accessibility once — it will stick from now on."
else
    echo "Something went wrong — identity not found after import." >&2
    exit 1
fi
