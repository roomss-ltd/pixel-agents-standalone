# agenttab/packaging/dmg-settings.py
# dmgbuild configuration for AgentTAB.

import os
import sys

# When dmgbuild is invoked as `dmgbuild -s dmg-settings.py "AgentTAB" out/AgentTAB-X.Y.Z.dmg "build/.../AgentTAB.app"`
# the trailing positional args after volume name and DMG path become defines.
# We resolve the .app path from the AGENTTAB_APP env var (set by build-dmg.sh).

application = os.environ.get("AGENTTAB_APP")
if not application or not os.path.isdir(application):
    print(f"error: AGENTTAB_APP env var must point to a built .app bundle (got: {application})", file=sys.stderr)
    sys.exit(1)

appname = "AgentTAB"

format = "UDZO"
size = "150M"

files = [application]
symlinks = {"Applications": "/Applications"}

# dmgbuild loads this file dynamically and does not populate __file__,
# so the AGENTTAB_ASSETS env var (set by build-dmg.sh) is used to locate assets.
assets_dir = os.environ.get("AGENTTAB_ASSETS", "")

# Optional: volume icon (falls back to default if file missing)
if assets_dir:
    volume_icon = os.path.join(assets_dir, "AppIcon.icns")
    if os.path.exists(volume_icon):
        icon = volume_icon

    # Background image (optional — fall back to no background if not present)
    bg = os.path.join(assets_dir, "dmg-background.png")
    if os.path.exists(bg):
        background = bg

window_rect = ((100, 100), (540, 380))

icon_locations = {
    "AgentTAB.app": (140, 200),
    "Applications": (400, 200),
}

default_view = "icon-view"
icon_size = 96
text_size = 12
