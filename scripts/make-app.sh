#!/bin/bash
# Assembles LessMouse.app from a release build, signs it, and zips it.
#
#   scripts/make-app.sh            # build + bundle + ad-hoc sign + dist/LessMouse.zip
#   CODESIGN_IDENTITY="Apple Development: …" scripts/make-app.sh
#
# Ad-hoc by default (no Apple Developer Program needed): Gatekeeper shows the
# "unidentified developer" flow on first launch, which README covers with the
# right-click-open steps. Set CODESIGN_IDENTITY to a real identity for
# Developer ID signing + notarization on your own machine.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.0}"
BUILD="${BUILD:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
BUNDLE_ID="${BUNDLE_ID:-dev.lessmouse.menubar}"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "▸ swift build -c release"
swift build -c release --disable-sandbox
BINARY=".build/release/LessMouse"

APP="dist/LessMouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ bundle"
cp "$BINARY" "$APP/Contents/MacOS/LessMouse"
sed -e "s/\$(VERSION)/$VERSION/" -e "s/\$(BUILD)/$BUILD/" -e "s/\$(BUNDLE_ID)/$BUNDLE_ID/" \
    scripts/app-template/Info.plist > "$APP/Contents/Info.plist"

# Icon: derive the 1024 art, then build the .icns via iconset.
swift scripts/make-icons.swift >/dev/null
ICONSET="dist/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
    sips -z $size $size assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
sips -z 1024 1024 assets/AppIcon-1024.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ codesign ($IDENTITY)"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1

echo "▸ zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/LessMouse.zip

echo "✓ dist/LessMouse.zip  (version $VERSION, build $BUILD)"
