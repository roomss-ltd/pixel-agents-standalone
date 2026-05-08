#!/bin/sh
# build-dmg.sh — produce an unsigned AgentTAB DMG ready for distribution.
#
# Usage:
#   agenttab/scripts/build-dmg.sh             # uses MARKETING_VERSION from project.yml (default 0.1.0)
#   agenttab/scripts/build-dmg.sh 1.2.3       # override version
#
# Artifacts:
#   /tmp/agenttab-build/   # xcodebuild derived data
#   out/AgentTAB-X.Y.Z.dmg # final DMG (gitignored)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTTAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AGENTTAB_DIR/.." && pwd)"

VERSION="${1:-0.1.0}"
BUILD_DIR="/tmp/agenttab-build"
APP_PATH="$BUILD_DIR/Build/Products/Release/AgentTAB.app"
OUT_DMG="$REPO_ROOT/out/AgentTAB-${VERSION}.dmg"

cd "$AGENTTAB_DIR"

echo "[build-dmg] Generating Xcode project..."
xcodegen generate >/dev/null

echo "[build-dmg] Building Release configuration..."
xcodebuild -project AgentTAB.xcodeproj \
           -scheme AgentTAB \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           build 2>&1 | tail -3

if [ ! -d "$APP_PATH" ]; then
    echo "[build-dmg] ERROR: $APP_PATH not produced — aborting" >&2
    exit 1
fi

echo "[build-dmg] Embedding AppIcon.icns..."
if [ -f "$AGENTTAB_DIR/assets/AppIcon.icns" ]; then
    cp "$AGENTTAB_DIR/assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
else
    echo "[build-dmg] WARNING: AppIcon.icns not found in assets/ — bundle will use default icon"
fi

echo "[build-dmg] Installing dmgbuild via pip if missing..."
if ! command -v dmgbuild >/dev/null 2>&1; then
    pip3 install --quiet --user dmgbuild
fi

echo "[build-dmg] Building DMG..."
mkdir -p "$REPO_ROOT/out"
rm -f "$OUT_DMG"
AGENTTAB_APP="$APP_PATH" \
AGENTTAB_ASSETS="$AGENTTAB_DIR/assets" \
dmgbuild \
    -s "$AGENTTAB_DIR/packaging/dmg-settings.py" \
    "AgentTAB" \
    "$OUT_DMG"

echo ""
echo "[build-dmg] Done."
echo "[build-dmg] DMG:    $OUT_DMG"
echo "[build-dmg] SHA-256:"
shasum -a 256 "$OUT_DMG"
