#!/usr/bin/env python3
"""Uploads assets/sfx/*.ogg to Roblox and writes the ids into AudioIds.lua.

Uses the Open Cloud Assets API (https://apis.roblox.com/assets/v1/assets).
Standard library only - no pip install needed.

One-time setup:
  1. Creator Dashboard -> Open Cloud -> API Keys -> Create API Key.
     Add the "Assets API" with read + write, and allow your IP (or 0.0.0.0/0).
  2. Your user id is the number in your profile URL
     (roblox.com/users/<id>/profile). For a group game use --group <groupId>.

Usage:
  set ROBLOX_API_KEY=...            (Windows)   /   export ROBLOX_API_KEY=...
  python tools/sfx/upload_audio.py --user 123456789
  python tools/sfx/upload_audio.py --user 123456789 --all
  python tools/sfx/upload_audio.py --user 123456789 --only ChestOpen LevelUp

Roblox limits audio uploads to 10 a month without ID verification (100 with
it). By default this uploads the PRIORITY list below - the ten sounds players
hear most. Already-uploaded cues (non-empty in AudioIds.lua) are skipped, so
re-running next month picks up where you left off.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX_DIR = os.path.join(ROOT, "assets", "sfx")
IDS_FILE = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "Audio", "AudioIds.lua")
API = "https://apis.roblox.com/assets/v1"

PRIORITY = [
    "UIClick",
    "CoinReward",
    "Purchase",
    "EggCrack",
    "HatchReveal_Common",
    "HatchReveal_Rare",
    "HatchReveal_Epic",
    "HatchReveal_Legendary",
    "ChestOpen",
    "Music_Hub",
]


def read_ids() -> dict[str, str]:
    ids: dict[str, str] = {}
    with open(IDS_FILE, encoding="utf-8") as f:
        for name, value in re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)"', f.read(), re.MULTILINE):
            ids[name] = value
    return ids


def write_ids(ids: dict[str, str]) -> None:
    with open(IDS_FILE, encoding="utf-8") as f:
        text = f.read()
    for name, value in ids.items():
        text = re.sub(rf'^(\s*{name}\s*=\s*)"[^"]*"', rf'\g<1>"{value}"', text, flags=re.MULTILINE)
    with open(IDS_FILE, "w", encoding="utf-8") as f:
        f.write(text)


def request(method: str, url: str, api_key: str, body: bytes | None = None, content_type: str | None = None) -> dict:
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", api_key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')}") from None


def upload(path: str, name: str, api_key: str, creator: dict) -> str:
    meta = {
        "assetType": "Audio",
        "displayName": f"BHW {name}"[:50],
        "description": "Brainrot Hatch Wars sound effect (original, synthesized).",
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        file_bytes = f.read()
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n".encode(),
        json.dumps(meta).encode(),
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(path)}\"\r\n"
        "Content-Type: audio/ogg\r\n\r\n".encode(),
        file_bytes,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    op = request("POST", f"{API}/assets", api_key, body, f"multipart/form-data; boundary={boundary}")
    op_path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/{op_path}", api_key)
    if not op.get("done"):
        raise RuntimeError("upload still processing after 2 minutes - check Creator Dashboard")
    if "error" in op:
        raise RuntimeError(json.dumps(op["error"]))
    return op["response"]["assetId"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument("--user", help="your Roblox user id")
    who.add_argument("--group", help="group id, for a group-owned game")
    parser.add_argument("--all", action="store_true", help="upload every cue, not just the priority ten")
    parser.add_argument("--only", nargs="+", metavar="CUE", help="upload just these cues")
    parser.add_argument("--dry-run", action="store_true", help="show what would be uploaded")
    args = parser.parse_args()

    api_key = os.environ.get("ROBLOX_API_KEY")
    if not api_key and not args.dry_run:
        print("Set the ROBLOX_API_KEY environment variable first (see the top of this file).")
        return 1
    creator = {"userId": args.user} if args.user else {"groupId": args.group}

    ids = read_ids()
    available = sorted(f[:-4] for f in os.listdir(SFX_DIR) if f.endswith(".ogg"))
    wanted = args.only or (available if args.all else PRIORITY)
    todo = [n for n in wanted if n in available and not ids.get(n)]
    unknown = [n for n in wanted if n not in available]
    if unknown:
        print(f"No such sound (run generate_sfx.py?): {', '.join(unknown)}")
    if not todo:
        print("Nothing to upload - every requested cue already has an id in AudioIds.lua.")
        return 0

    print(f"Uploading {len(todo)} sound(s): {', '.join(todo)}")
    for name in todo:
        if args.dry_run:
            print(f"  [dry run] {name}")
            continue
        try:
            asset_id = upload(os.path.join(SFX_DIR, f"{name}.ogg"), name, api_key, creator)
        except RuntimeError as e:
            print(f"  {name}: FAILED - {e}")
            print("  (Monthly audio limit reached? Re-run next month; finished uploads are saved.)")
            break
        ids[name] = f"rbxassetid://{asset_id}"
        write_ids(ids)  # save after each one, so a later failure loses nothing
        print(f"  {name}: rbxassetid://{asset_id}")
    print("Done. Commit src/ReplicatedStorage/Shared/Audio/AudioIds.lua (Rojo syncs it into Studio).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
