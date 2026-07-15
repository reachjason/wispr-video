#!/bin/bash
# Compiles the Swift sources and assembles a signed WisprVideo.app bundle.
# Usage: ./build.sh          (build only)
#        ./build.sh run      (build then launch)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Wispr Video.app"
BIN="$APP/Contents/MacOS/WisprVideo"

echo "▶ Compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework Carbon \
    -framework ScreenCaptureKit \
    -framework CoreImage \
    -o "$BIN" \
    "$ROOT"/Sources/WisprVideo/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Prefer the stable local identity (created by tools/make-signing-cert.sh) so
# macOS keeps granted permissions across rebuilds; fall back to ad-hoc.
IDENTITY="Wispr Video Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    security unlock-keychain -p wisprdev wispr-signing.keychain 2>/dev/null || true
    echo "▶ Signing with '$IDENTITY'…"
    SIGN_ID="$IDENTITY"
else
    echo "▶ Signing (ad-hoc — run tools/make-signing-cert.sh so permissions persist)…"
    SIGN_ID="-"
fi
codesign --force --sign "$SIGN_ID" \
    --entitlements "$ROOT/Resources/WisprVideo.entitlements" \
    "$APP"

echo "✅ Built: $APP"

if [[ "${1:-}" == "run" ]]; then
    echo "▶ Launching…"
    killall WisprVideo 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi
