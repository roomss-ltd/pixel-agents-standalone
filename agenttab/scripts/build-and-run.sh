#!/bin/sh
# build-and-run.sh — Generate, build, and launch AgentTAB.
#
# Build artifacts live in /tmp (NOT inside ~/Desktop) so the unsigned
# binary never triggers the macOS Desktop-access TCC prompt.
#
# Usage:
#   agenttab/scripts/build-and-run.sh             # build + launch (foreground)
#   agenttab/scripts/build-and-run.sh --no-launch # build only, no launch
#   agenttab/scripts/build-and-run.sh &           # background build + launch
#
# To kill the running app afterwards: pkill -x AgentTAB

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTTAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/agenttab-build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/AgentTAB.app"

LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
    esac
done

cd "$AGENTTAB_DIR"

echo "[AgentTAB] Killing any running instance..."
pkill -x AgentTAB 2>/dev/null || true

echo "[AgentTAB] Generating Xcode project..."
xcodegen generate >/dev/null

echo "[AgentTAB] Building (artifacts: $BUILD_DIR)..."
xcodebuild -project AgentTAB.xcodeproj \
           -scheme AgentTAB \
           -configuration Debug \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           build 2>&1 | tail -3

if [ "$LAUNCH" -eq 1 ]; then
    echo "[AgentTAB] Launching $APP_PATH..."
    open -n "$APP_PATH"
    sleep 1
    PID=$(pgrep -x AgentTAB || echo "")
    if [ -n "$PID" ]; then
        echo "[AgentTAB] Running. PID: $PID"
        echo "[AgentTAB] To stop: pkill -x AgentTAB"
    else
        echo "[AgentTAB] Process not detected after launch — check Console.app for errors."
        exit 1
    fi
else
    echo "[AgentTAB] Build complete. App at: $APP_PATH"
fi
