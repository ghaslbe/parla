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

# Ad-hoc code signature. TCC (Accessibility / Input Monitoring / Mic) keys the
# permission grant to the signature, so a stable ad-hoc signature keeps grants
# across rebuilds on the dev machine. Replace with a Developer ID for release.
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - \
    --options runtime \
    --identifier dev.parla.Parla \
    "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
