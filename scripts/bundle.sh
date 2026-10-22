#!/usr/bin/env bash
# Assemble Parla.app from the SwiftPM build product.
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Parla.app"
BIN_DIR="$ROOT/.build/$CONFIG"

echo "==> ensuring whisper.cpp is built"
bash "$ROOT/scripts/build-whisper.sh"

echo "==> swift build -c $CONFIG"
( cd "$ROOT" && swift build -c "$CONFIG" )

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Parla" "$APP/Contents/MacOS/Parla"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Localizations (en / de): Localizable.strings + InfoPlist.strings per .lproj.
for lproj in "$ROOT/Resources/"*.lproj; do
    [ -d "$lproj" ] || continue
    name="$(basename "$lproj")"
    mkdir -p "$APP/Contents/Resources/$name"
    cp "$lproj/"* "$APP/Contents/Resources/$name/"
done

# Code signature. TCC (Accessibility / Input Monitoring / Microphone) keys each
# permission grant to the app's code identity. An ad-hoc signature's identity
# (cdhash) changes on every rebuild, so grants go stale and must be re-added
# each time. Signing with a real, stable identity keeps grants across rebuilds.
#
# Picks, in order: $PARLA_SIGN_ID, else the first codesigning identity in the
# keychain (e.g. "Apple Development: …"), else ad-hoc.
SIGN_ID="${PARLA_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/[0-9]+\)/{print $2; exit}')"
fi
if [ -n "$SIGN_ID" ]; then
    echo "==> codesign with identity $SIGN_ID"
    codesign --force --deep --sign "$SIGN_ID" --identifier dev.parla.Parla "$APP"
else
    echo "==> codesign (ad-hoc — grants will reset on each rebuild)"
    codesign --force --deep --sign - --identifier dev.parla.Parla "$APP"
fi

echo "==> done: $APP"
