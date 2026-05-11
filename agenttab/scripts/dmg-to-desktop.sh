#!/bin/zsh
# dmg-to-desktop.sh — one-shot: build AgentTAB in Release, package the
# .app into a styled DMG with a drag-to-Applications layout, drop it on
# ~/Desktop. No Python deps — pure xcodebuild + hdiutil + iconutil +
# osascript.
#
# The DMG is ad-hoc codesigned. macOS Gatekeeper still nags first-time
# launchers because the bundle isn't notarised; the included
# "Open Safely.command" helper strips the quarantine attribute so
# AgentTAB launches normally. INSTALL.txt explains the steps.
#
# Usage:
#   agenttab/scripts/dmg-to-desktop.sh             # version from Info.plist
#   agenttab/scripts/dmg-to-desktop.sh 0.2.0       # override version
#
# Output:
#   ~/Desktop/AgentTAB-X.Y.Z.dmg
#   prints the SHA-256 so peers can verify the file they received.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
AGENTTAB_DIR="${SCRIPT_DIR:h}"
PROJECT="$AGENTTAB_DIR/AgentTAB.xcodeproj"
INFO_PLIST="$AGENTTAB_DIR/AgentTAB/App/Info.plist"
ASSETS="$AGENTTAB_DIR/assets"

# ─── Resolve version ───────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
    VERSION="$1"
else
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo '0.1.0')"
fi

VOL_NAME="AgentTAB ${VERSION}"
DMG_PATH="$HOME/Desktop/AgentTAB-${VERSION}.dmg"
WORK_DIR="$(mktemp -d -t agenttab-dmg)"
trap 'rm -rf "$WORK_DIR"' EXIT
STAGE="$WORK_DIR/stage"
BUILD_DIR="$WORK_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/AgentTAB.app"

# ─── Ensure project exists (xcodegen generates it from project.yml) ─
if [[ ! -d "$PROJECT" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "[dmg] ERROR: AgentTAB.xcodeproj is missing and 'xcodegen' is not installed." >&2
        echo "       Install it via:  brew install xcodegen" >&2
        exit 1
    fi
    echo "[dmg] Generating AgentTAB.xcodeproj from project.yml..."
    (cd "$AGENTTAB_DIR" && xcodegen generate) >/dev/null
fi

# ─── Build ─────────────────────────────────────────────────────────
echo "[dmg] Building AgentTAB ${VERSION} (Release)..."
xcodebuild -project "$PROJECT" \
           -scheme AgentTAB \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           build > "$WORK_DIR/build.log" 2>&1 || {
    echo "[dmg] build failed — last 40 lines of build.log:" >&2
    tail -40 "$WORK_DIR/build.log" >&2
    exit 1
}

if [[ ! -d "$APP_PATH" ]]; then
    echo "[dmg] ERROR: built app not found at $APP_PATH" >&2
    exit 1
fi

# Refresh the multi-resolution icon from the iconset (xcodebuild ships
# whatever's already in Resources; rebuilding guarantees all sizes).
if [[ -d "$ASSETS/AppIcon.iconset" ]]; then
    echo "[dmg] Refreshing AppIcon.icns from iconset..."
    iconutil -c icns "$ASSETS/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

echo "[dmg] Ad-hoc codesigning (hardened runtime)..."
codesign --force --deep --options=runtime --sign - "$APP_PATH"

# ─── Stage layout ──────────────────────────────────────────────────
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/AgentTAB.app"
ln -s /Applications "$STAGE/Applications"

# Hidden background for the styled DMG window.
if [[ -f "$ASSETS/dmg-background.png" ]]; then
    mkdir -p "$STAGE/.background"
    cp "$ASSETS/dmg-background.png" "$STAGE/.background/background.png"
fi

# INSTALL.txt — recipient-facing instructions.
cat > "$STAGE/INSTALL.txt" <<'TXT'
AgentTAB — install instructions
================================

1.  Drag "AgentTAB.app" onto the Applications shortcut in this window.

2.  First launch only — macOS will refuse with a Gatekeeper warning
    ("Apple could not verify …"). Pick ONE:

    a) Easiest: double-click "Open Safely.command" inside this DMG.
       It strips the quarantine flag from /Applications/AgentTAB.app
       so macOS will launch it normally.

    b) Manual: open  System Settings → Privacy & Security  → scroll
       down → click "Open Anyway" next to AgentTAB.

    c) Terminal:
       xattr -dr com.apple.quarantine /Applications/AgentTAB.app

3.  Launch AgentTAB from Applications or Launchpad. The notch overlay
    appears next to your menu bar. Done.

If the helper doesn't work, run option (c) from Terminal.
TXT

# Open Safely.command — one-click un-quarantine helper.
cat > "$STAGE/Open Safely.command" <<'CMD'
#!/bin/zsh
# Strip the Gatekeeper quarantine flag from AgentTAB and launch it.
# Run by double-clicking this file inside the DMG.
set -e
APP="/Applications/AgentTAB.app"
if [[ ! -d "$APP" ]]; then
    osascript -e 'display alert "AgentTAB not installed" message "Drag AgentTAB.app to Applications first, then run this helper again." as critical'
    exit 1
fi
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/usr/bin/open "$APP"
CMD
chmod +x "$STAGE/Open Safely.command"

# ─── Build the read/write DMG ──────────────────────────────────────
echo "[dmg] Creating ${DMG_PATH:t}..."
rm -f "$DMG_PATH" "$WORK_DIR/rw.dmg"

hdiutil create -volname "$VOL_NAME" \
               -fs HFS+ \
               -fsargs "-c c=64,a=16,e=16" \
               -srcfolder "$STAGE" \
               -format UDRW \
               -ov \
               "$WORK_DIR/rw.dmg" > /dev/null

# ─── Mount + apply Finder window layout ────────────────────────────
MOUNT_DIR="$(mktemp -d -t agenttab-dmg-mount)"
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$WORK_DIR/rw.dmg" > /dev/null

# Finder needs a few seconds to register the new disk before
# AppleScript can address it by name. Poll up to ~10s before giving up.
sleep 3

# Layout step is COSMETIC — wrap it so a failure here doesn't abort
# the whole DMG build (set -e would otherwise discard the rest of the
# script). Retry the AppleScript a few times because Finder sometimes
# refuses the first attempt.
LAYOUT_OK=0
for attempt in 1 2 3 4; do
    if osascript <<APPLESCRIPT 2>"$WORK_DIR/osa.err"
tell application "Finder"
    activate
    delay 0.5
    tell disk "$VOL_NAME"
        open
        delay 1.0
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 800, 580}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "AgentTAB.app"        of container window to {165, 200}
        set position of item "Applications"        of container window to {435, 200}
        set position of item "INSTALL.txt"         of container window to {165, 340}
        set position of item "Open Safely.command" of container window to {435, 340}
        update without registering applications
        delay 0.5
        close
    end tell
end tell
APPLESCRIPT
    then
        LAYOUT_OK=1
        break
    fi
    sleep 2
done

if [[ $LAYOUT_OK -ne 1 ]]; then
    echo "[dmg] WARNING: AppleScript layout failed after retries — DMG will use Finder defaults."
    echo "[dmg]          (last error: $(cat "$WORK_DIR/osa.err" 2>/dev/null | head -3))"
    echo "[dmg]          Tip: grant Terminal access in"
    echo "[dmg]               System Settings → Privacy & Security → Automation → Terminal → Finder."
fi

# Hide the .command file's extension (cosmetic — fine if it fails).
SetFile -a E "$MOUNT_DIR/Open Safely.command" 2>/dev/null || true

sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force || true
rm -rf "$MOUNT_DIR"

# ─── Convert to compressed read-only ───────────────────────────────
hdiutil convert "$WORK_DIR/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" > /dev/null

# ─── Report ────────────────────────────────────────────────────────
SIZE_MB=$(( $(stat -f%z "$DMG_PATH") / 1024 / 1024 ))
echo ""
echo "[dmg] Done."
echo "[dmg]   path:   $DMG_PATH"
echo "[dmg]   size:   ${SIZE_MB} MB"
echo "[dmg]   sha256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "Recipients: double-click the DMG, drag AgentTAB.app onto Applications,"
echo "then double-click \"Open Safely.command\" inside the DMG to strip the"
echo "quarantine flag and launch. INSTALL.txt has the same steps written out."
echo ""
echo "For a warning-free install, you need an Apple Developer ID and a"
echo "notarised build (\`xcrun notarytool submit …\` after Developer ID signing)."
