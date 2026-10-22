#!/bin/bash
# Builds DragWheel.app (macOS 14+).
#
#   ./build.sh                       Apple Silicon or Intel, whichever this Mac is
#   ./build.sh --universal           one binary for both
#   ./build.sh --universal --package also writes dist/DragWheel-<version>-macOS.zip and .dmg
#
# The app is signed ad-hoc with the hardened runtime. There is no Apple Developer ID,
# so Gatekeeper asks people to confirm the first launch (see README).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
APP="$DIR/build/DragWheel.app"
DIST="$ROOT/dist"
BUNDLE_ID="io.github.nico43245.dragwheel"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"

UNIVERSAL=0
PACKAGE=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --package) PACKAGE=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

SWIFT_ARGS=(-c release --package-path "$DIR")
if [ "$UNIVERSAL" = 1 ]; then SWIFT_ARGS+=(--arch arm64 --arch x86_64); fi

echo "→ Compiling DragWheel $VERSION…"
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/DragWheel"

echo "→ Assembling DragWheel.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DragWheel"
cp "$DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

if [ ! -f "$DIR/build/AppIcon.icns" ]; then
    echo "→ Drawing app icon…"
    swift "$DIR/scripts/make_icon.swift" "$DIR/build/AppIcon.iconset"
    iconutil -c icns "$DIR/build/AppIcon.iconset" -o "$DIR/build/AppIcon.icns"
    rm -rf "$DIR/build/AppIcon.iconset"
fi
cp "$DIR/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing (ad-hoc, hardened runtime)…"
codesign --force --options runtime --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/DragWheel"

if [ "$PACKAGE" = 1 ]; then
    echo "→ Packaging…"
    mkdir -p "$DIST"
    ditto -c -k --keepParent "$APP" "$DIST/DragWheel-$VERSION-macOS.zip"

    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DIST/DragWheel-$VERSION-macOS.dmg"
    hdiutil create -quiet -volname "DragWheel $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
        "$DIST/DragWheel-$VERSION-macOS.dmg"
    rm -rf "$STAGE"
    ls -lh "$DIST"
fi

echo "✓ Built $APP"
