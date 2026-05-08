#!/bin/sh
# release.sh — build, sign, and (optionally) publish a new AgentTAB release.
#
# Usage:
#   agenttab/scripts/release.sh 0.1.0
#
# Produces:
#   out/AgentTAB-X.Y.Z.dmg
#   out/appcast.xml
# Optionally uploads both to Cloudflare R2 (bucket: updates-agenttab).

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: release.sh <version>" >&2
    exit 64
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTTAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AGENTTAB_DIR/.." && pwd)"

DMG="$REPO_ROOT/out/AgentTAB-${VERSION}.dmg"
APPCAST="$REPO_ROOT/out/appcast.xml"
NOTES="$AGENTTAB_DIR/release-notes/${VERSION}.html"

# Resolve sign_update binary (M7.1 downloaded Sparkle CLI to /tmp/sparkle-cli/bin/)
SIGN_UPDATE="${SIGN_UPDATE:-/tmp/sparkle-cli/bin/sign_update}"
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "[release] error: sign_update not at $SIGN_UPDATE" >&2
    echo "[release] re-download Sparkle CLI: see agenttab/SPARKLE-KEYS.md" >&2
    exit 1
fi

# 1. Build DMG
"$AGENTTAB_DIR/scripts/build-dmg.sh" "$VERSION"

# 2. Verify release notes exist
if [ ! -f "$NOTES" ]; then
    echo "[release] error: release notes not found at $NOTES" >&2
    echo "[release] create it (HTML, CDATA-safe) before tagging." >&2
    exit 1
fi

# 3. Sign the DMG with the EdDSA private key (Sparkle pulls from Keychain)
echo "[release] Signing $DMG..."
SIGNATURE=$("$SIGN_UPDATE" "$DMG")
echo "[release] Signature: $SIGNATURE"

# 4. Update appcast.xml
echo "[release] Updating appcast..."
python3 "$AGENTTAB_DIR/scripts/update_appcast.py" \
    --version "$VERSION" \
    --dmg "$DMG" \
    --signature "$SIGNATURE" \
    --notes "$NOTES" \
    --out "$APPCAST"

# 5. Upload to Cloudflare R2 if wrangler is available
if command -v wrangler >/dev/null 2>&1; then
    echo "[release] Uploading to Cloudflare R2..."
    if wrangler r2 object put "updates-agenttab/releases/AgentTAB-${VERSION}.dmg" \
        --file="$DMG" 2>/dev/null && \
       wrangler r2 object put "updates-agenttab/appcast.xml" \
        --file="$APPCAST" 2>/dev/null; then
        echo "[release] R2 upload OK."
    else
        echo "[release] WARNING: wrangler upload failed."
        echo "[release] Run manually: wrangler r2 object put updates-agenttab/releases/AgentTAB-${VERSION}.dmg --file=$DMG"
        echo "[release] And:           wrangler r2 object put updates-agenttab/appcast.xml --file=$APPCAST"
    fi
else
    echo "[release] wrangler not installed — skipping R2 upload."
    echo "[release] Manual upload commands:"
    echo "  wrangler r2 object put updates-agenttab/releases/AgentTAB-${VERSION}.dmg --file=$DMG"
    echo "  wrangler r2 object put updates-agenttab/appcast.xml --file=$APPCAST"
fi

# 6. Summary
echo ""
echo "[release] Released $VERSION."
echo "[release] DMG:     $DMG"
echo "[release] Appcast: $APPCAST"
echo "[release] SHA-256:"
shasum -a 256 "$DMG"
echo ""
echo "[release] Tag it: git tag v$VERSION && git push --tags"
