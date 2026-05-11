#!/bin/zsh
# install.sh — build AgentTab from source on the local machine, install
# to /Applications, and launch it. Because the user builds the app
# themselves, macOS Gatekeeper does NOT block first launch — no
# "Apple could not verify…" warning.
#
# Flags:
#   --build-only      Stop after the .app is built. Output ends in build/.
#   --no-launch       Install but don't open AgentTab afterwards.

set -euo pipefail

BUILD_ONLY=0
LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=1 ;;
        --no-launch)  LAUNCH=0    ;;
        -h|--help)
            sed -n '2,11p' "$0"
            exit 0
            ;;
    esac
done

SCRIPT_DIR="${0:A:h}"
AGENTTAB_DIR="${SCRIPT_DIR:h}"
PROJECT="$AGENTTAB_DIR/AgentTAB.xcodeproj"
ASSETS="$AGENTTAB_DIR/assets"

BUILD_DIR="$AGENTTAB_DIR/build/derived"
APP_OUT="$AGENTTAB_DIR/build/AgentTAB.app"

# ─── Sanity checks ─────────────────────────────────────────────────
if ! command -v xcodebuild >/dev/null 2>&1; then
    cat <<'TXT' >&2
Xcode command-line tools are required.

Install them first:
    xcode-select --install

Then re-run:
    make install
TXT
    exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
    echo "[install] ERROR: project not found at $PROJECT" >&2
    exit 1
fi

# ─── Build ─────────────────────────────────────────────────────────
echo "[install] Building AgentTab (Release)..."
mkdir -p "$AGENTTAB_DIR/build"
rm -rf "$BUILD_DIR" "$APP_OUT"

xcodebuild -project "$PROJECT" \
           -scheme AgentTAB \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           build > "$AGENTTAB_DIR/build/build.log" 2>&1 || {
    echo "[install] build failed — last 40 lines of build.log:" >&2
    tail -40 "$AGENTTAB_DIR/build/build.log" >&2
    echo ""
    echo "Full log: $AGENTTAB_DIR/build/build.log" >&2
    exit 1
}

BUILT_APP="$BUILD_DIR/Build/Products/Release/AgentTAB.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "[install] ERROR: build succeeded but $BUILT_APP not found" >&2
    exit 1
fi

# Refresh the multi-resolution icon (xcodebuild ships whatever's already
# in Resources/; this guarantees all sizes from the iconset are bundled).
if [[ -d "$ASSETS/AppIcon.iconset" ]]; then
    iconutil -c icns "$ASSETS/AppIcon.iconset" -o "$BUILT_APP/Contents/Resources/AppIcon.icns"
fi

# Re-sign frameworks BEFORE the outer bundle. Sparkle ships with a real
# Team-ID signature, and dyld's library validation refuses to load it
# when the parent binary is ad-hoc signed ("different Team IDs"). We
# bottom-up re-sign so every nested binary has the same identity.
if [[ -d "$BUILT_APP/Contents/Frameworks" ]]; then
    find "$BUILT_APP/Contents/Frameworks" -type d -name "*.framework" -mindepth 1 -maxdepth 1 | while read -r fw; do
        codesign --force --deep --sign - "$fw" >/dev/null 2>&1 || true
    done
fi
# Now ad-hoc sign the outer bundle. NO `--options runtime` — hardened
# runtime requires a notarised Team-ID signature; ad-hoc + hardened
# runtime is exactly the combo that triggers the dyld team-id check.
codesign --force --deep --sign - "$BUILT_APP" >/dev/null 2>&1 || true

# Mirror the built app to build/AgentTAB.app for inspection.
cp -R "$BUILT_APP" "$APP_OUT"

if [[ $BUILD_ONLY -eq 1 ]]; then
    echo "[install] Build only. Output: $APP_OUT"
    exit 0
fi

# ─── Install to /Applications ──────────────────────────────────────
DEST="/Applications/AgentTAB.app"
echo "[install] Installing to $DEST..."

# Quit any running instance so we can overwrite without "in use" errors.
pkill -x AgentTAB 2>/dev/null || true
sleep 0.5

# Most user-admin Macs allow writes to /Applications without sudo.
# Fall back to AppleScript admin auth if not.
if rm -rf "$DEST" 2>/dev/null && cp -R "$BUILT_APP" "$DEST" 2>/dev/null; then
    :
else
    echo "[install] /Applications needs admin auth — prompting..."
    SRC_ESC="${BUILT_APP//\"/\\\"}"
    DEST_ESC="${DEST//\"/\\\"}"
    osascript -e "do shell script \"rm -rf '$DEST_ESC' && cp -R '$SRC_ESC' '$DEST_ESC'\" with administrator privileges"
fi

# Strip the quarantine attribute in case the source was downloaded.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Force LaunchServices to re-read the bundle (picks up the new icon
# without a logout / Finder restart).
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f -R "$DEST" >/dev/null 2>&1 || true

# ─── Launch ────────────────────────────────────────────────────────
if [[ $LAUNCH -eq 1 ]]; then
    open "$DEST"
    echo "[install] AgentTab installed and launched."
else
    echo "[install] AgentTab installed (not launched, --no-launch)."
fi

echo "[install] Location: $DEST"
