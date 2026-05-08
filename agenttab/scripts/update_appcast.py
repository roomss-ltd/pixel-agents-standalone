#!/usr/bin/env python3
"""Update agenttab/out/appcast.xml with a new release item.

Usage:
    update_appcast.py --version 0.1.0 \
                      --dmg out/AgentTAB-0.1.0.dmg \
                      --signature 'sparkle:edSignature="..."' \
                      --notes agenttab/release-notes/0.1.0.html \
                      --out out/appcast.xml
"""
import argparse
import datetime
import os
import sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--dmg", required=True)
    p.add_argument("--signature", required=True,
                   help="Either the full sparkle:edSignature=\"...\" attribute or just the base64 signature.")
    p.add_argument("--notes", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--template", default="agenttab/packaging/appcast-template.xml")
    args = p.parse_args()

    if not os.path.exists(args.dmg):
        print(f"error: dmg not found at {args.dmg}", file=sys.stderr)
        return 1
    if not os.path.exists(args.notes):
        print(f"error: release notes not found at {args.notes}", file=sys.stderr)
        return 1

    dmg_size = os.path.getsize(args.dmg)
    release_date = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S +0000")
    notes_html = Path(args.notes).read_text()

    # Normalize signature to just the base64 (strip the attribute wrapper if present).
    sig = args.signature.strip()
    if sig.startswith("sparkle:edSignature="):
        sig = sig.split('"')[1]

    new_item = f"""    <item>
      <title>Version {args.version}</title>
      <description><![CDATA[{notes_html}]]></description>
      <pubDate>{release_date}</pubDate>
      <enclosure
        url="https://updates.agenttab.roomss.dev/releases/AgentTAB-{args.version}.dmg"
        sparkle:version="{args.version}"
        sparkle:edSignature="{sig}"
        length="{dmg_size}"
        type="application/octet-stream"/>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
"""

    if os.path.exists(args.out):
        text = Path(args.out).read_text()
        # Insert the new item right after </language> so the newest is on top.
        idx = text.index("</language>") + len("</language>")
        text = text[:idx] + "\n" + new_item + text[idx:]
    else:
        template = Path(args.template).read_text()
        text = template.replace("    {items}", new_item.rstrip())

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(text)
    print(f"Appcast updated: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
