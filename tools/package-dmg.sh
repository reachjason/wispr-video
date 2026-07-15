#!/bin/bash
# Builds a UNIVERSAL (arm64 + x86_64) WisprVideo.app and wraps it in a
# distributable .dmg with an Applications drop-target and open instructions.
# Usage: ./tools/package-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
SRC="$ROOT/Sources/WisprVideo"
APP="$BUILD/Wispr Video.app"
VERSION="1.0"
DMG="$BUILD/WisprVideo-$VERSION.dmg"

mkdir -p "$BUILD"

echo "▶ Compiling universal binary (arm64 + x86_64)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

FRAMEWORKS=(-framework AppKit -framework AVFoundation -framework SwiftUI -framework Carbon)
swiftc -O "${FRAMEWORKS[@]}" -target arm64-apple-macos13.0  -o "$BUILD/wv-arm64"  "$SRC"/*.swift
swiftc -O "${FRAMEWORKS[@]}" -target x86_64-apple-macos13.0 -o "$BUILD/wv-x86_64" "$SRC"/*.swift
lipo -create "$BUILD/wv-arm64" "$BUILD/wv-x86_64" -output "$APP/Contents/MacOS/WisprVideo"
rm -f "$BUILD/wv-arm64" "$BUILD/wv-x86_64"

cp "$ROOT/Resources/Info.plist"   "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▶ Signing (ad-hoc)…"
codesign --force --sign - --entitlements "$ROOT/Resources/WisprVideo.entitlements" "$APP"

echo "▶ Architectures:"
lipo -info "$APP/Contents/MacOS/WisprVideo"

echo "▶ Building DMG…"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/HowToOpen.txt" "$STAGE/How to Open.txt"
rm -f "$DMG"
hdiutil create -volname "Wispr Video" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✅ Wrote $DMG"
du -h "$DMG"
