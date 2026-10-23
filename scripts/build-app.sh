#!/usr/bin/env bash
# Builds "DeX for Mac.app" into dist/, embedding adb + scrcpy.
#
# Usage:
#   ./scripts/build-app.sh [--dmg] [--no-clean]
#
# The app is ad-hoc signed, so it can be run locally without an Apple
# Developer account. It is not notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DeX for Mac"
EXECUTABLE="DeXMac"
BUNDLE_ID="com.dexmac.DeXMac"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
TOOLS="$ROOT/vendor/tools"
BUILD_DMG=0

for argument in "$@"; do
    case "$argument" in
        --dmg) BUILD_DMG=1 ;;
        --no-clean) ;;
        *) echo "error: unknown option $argument" >&2; exit 1 ;;
    esac
done

cd "$ROOT"

# MARK: - Tools

if [ ! -x "$TOOLS/scrcpy" ] || [ ! -x "$TOOLS/adb" ]; then
    echo "Tools are missing; fetching them…"
    "$ROOT/scripts/fetch-tools.sh" "$TOOLS"
fi

case "$(uname -m)" in
    arm64) HOST_ASSET_ARCH="arm64" ;;
    x86_64) HOST_ASSET_ARCH="x86_64" ;;
    *) HOST_ASSET_ARCH="" ;;
esac

if [ -n "$HOST_ASSET_ARCH" ] && ! file "$TOOLS/scrcpy" | grep -q "$HOST_ASSET_ARCH"; then
    echo "Bundled tools do not match this Mac ($HOST_ASSET_ARCH); downloading the correct build…"
    "$ROOT/scripts/fetch-tools.sh" "$TOOLS" --force
fi

# MARK: - Icon

ICON="$ROOT/Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "Generating app icon…"
    PREFIX="$(mktemp -d "${TMPDIR:-/tmp}/dexmac-icon.XXXXXX")"
    ICONSET="$PREFIX/AppIcon.iconset"
    mkdir -p "$ICONSET"

    MASTER="$ROOT/Resources/AppIcon-1024.png"
    if [ ! -f "$MASTER" ]; then
        "$ROOT/scripts/make-icon.sh" "$MASTER"
    fi

    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    done
    sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET" -o "$ICON"
    rm -rf "$PREFIX"
fi

# MARK: - Build

echo "Building release binary…"
swift build -c release --product "$EXECUTABLE"
BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE"

if [ ! -x "$BINARY" ]; then
    echo "error: release binary not found at $BINARY" >&2
    exit 1
fi

# MARK: - Assemble bundle

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tools"

cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
chmod 755 "$APP/Contents/MacOS/$EXECUTABLE"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
printf 'APPL????' > "$APP/Contents/PkgInfo"

for name in adb scrcpy scrcpy-server LICENSE scrcpy.1; do
    if [ -f "$TOOLS/$name" ]; then
        cp "$TOOLS/$name" "$APP/Contents/Resources/tools/$name"
    fi
done
chmod 755 "$APP/Contents/Resources/tools/adb" "$APP/Contents/Resources/tools/scrcpy"

# Bundle identifier guard: the binary and Info.plist must agree.
CURRENT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$CURRENT_ID" != "$BUNDLE_ID" ]; then
    echo "error: unexpected bundle id '$CURRENT_ID'" >&2
    exit 1
fi

# MARK: - Sign

echo "Signing (ad-hoc)…"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/Resources/tools/adb" >/dev/null 2>&1 || true
codesign --force --sign - "$APP/Contents/Resources/tools/scrcpy" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Signature OK."

# MARK: - DMG

if [ "$BUILD_DMG" -eq 1 ]; then
    echo "Creating DMG…"
    STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dexmac-dmg.XXXXXX")"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    DMG="$DIST/DeX-for-Mac.dmg"
    rm -f "$DMG"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -quiet -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "Created $DMG"
fi

echo
echo "Built $APP"
du -sh "$APP"
