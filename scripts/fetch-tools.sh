#!/usr/bin/env bash
# Downloads the pinned scrcpy release (which already contains adb) into
# vendor/tools so build-app.sh can embed it in the app bundle.
#
# Usage:
#   ./scripts/fetch-tools.sh [destination] [--force]
#
# Env:
#   SCRCPY_VERSION   Override the pinned release (default: 5.0.1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${SCRCPY_VERSION:-5.0.1}"

DEST="$ROOT/vendor/tools"
FORCE=0
for argument in "$@"; do
    case "$argument" in
        --force) FORCE=1 ;;
        *) DEST="$argument" ;;
    esac
done

if [ -x "$DEST/scrcpy" ] && [ -x "$DEST/adb" ] && [ "$FORCE" -ne 1 ]; then
    echo "Tools already present in $DEST (use --force to refresh)."
    exit 0
fi

case "$(uname -m)" in
    arm64) ARCH="aarch64" ;;
    x86_64) ARCH="x86_64" ;;
    *)
        echo "error: unsupported architecture $(uname -m)" >&2
        exit 1
        ;;
esac

ASSET="scrcpy-macos-${ARCH}-v${VERSION}.tar.gz"
BASE_URL="https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dexmac-tools.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "Downloading scrcpy ${VERSION} for ${ARCH}…"
curl --fail --location --retry 3 --retry-delay 2 \
    --output "$WORK/$ASSET" "$BASE_URL/$ASSET"
curl --fail --location --retry 3 --retry-delay 2 \
    --output "$WORK/SHA256SUMS.txt" "$BASE_URL/SHA256SUMS.txt"

echo "Verifying checksum…"
(
    cd "$WORK"
    grep -E "[ *]${ASSET//./\\.}\$" SHA256SUMS.txt > expected.txt
    if [ ! -s expected.txt ]; then
        echo "error: SHA256SUMS.txt has no entry for $ASSET" >&2
        exit 1
    fi
    shasum -a 256 --check expected.txt
)

echo "Unpacking…"
mkdir -p "$WORK/unpacked"
tar -xzf "$WORK/$ASSET" -C "$WORK/unpacked"

SOURCE="$(find "$WORK/unpacked" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
if [ -z "$SOURCE" ]; then
    SOURCE="$WORK/unpacked"
fi

for required in adb scrcpy scrcpy-server; do
    if [ ! -f "$SOURCE/$required" ]; then
        echo "error: the archive did not contain $required" >&2
        exit 1
    fi
done

mkdir -p "$DEST"
for name in adb scrcpy scrcpy-server LICENSE scrcpy.1; do
    if [ -f "$SOURCE/$name" ]; then
        cp -f "$SOURCE/$name" "$DEST/$name"
    fi
done
chmod 755 "$DEST/adb" "$DEST/scrcpy"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Installed into $DEST:"
ls -lh "$DEST"
"$DEST/scrcpy" --version
