#!/bin/bash
# Generates Resources/AppIcon.icns from tools/makeicon.swift.
# Run once (or whenever you change the icon design); the .icns is committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SRC="$TMP/icon_1024.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "▶ Rendering base icon…"
swift "$ROOT/tools/makeicon.swift" "$SRC"

echo "▶ Generating iconset sizes…"
gen() { sips -z "$1" "$1" "$SRC" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

echo "▶ Building .icns…"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

echo "✅ Wrote Resources/AppIcon.icns"
