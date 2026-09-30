#!/usr/bin/env python3
"""Uploads the prepared Brainrot models (assets/models/*.fbx) to Roblox and
writes their ids into src/ReplicatedStorage/Shared/Assets/ModelIds.lua.

At the next server start, ModelAssetService loads them into the game - no
Studio import needed. Uses the same Open Cloud API key as upload_audio.py
(Assets API, read + write). Standard library only.

  set ROBLOX_API_KEY=...      (Windows)  /  export ROBLOX_API_KEY=...
  python tools/models/upload_models.py --user <your user id>
  python tools/models/upload_models.py --group <group id>      # group game

The game must be owned by the same user/group, or the game can't load them.
Already-uploaded entries are skipped, so re-running is safe.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "sfx"))
from upload_audio import request, upload_file  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
IDS_FILE = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "Assets", "ModelIds.lua")


def read_entries() -> dict[str, dict[str, str]]:
    text = open(IDS_FILE, encoding="utf-8").read()
    return {
        name: {"Model": model, "Texture": texture}
        for name, model, texture in re.findall(r'(\w+) = \{ Model = "([^"]*)", Texture = "([^"]*)" \}', text)
    }


def write_entry(name: str, model: str, texture: str) -> None:
    text = open(IDS_FILE, encoding="utf-8").read()
    text = re.sub(
        rf'{name} = \{{ Model = "[^"]*", Texture = "[^"]*" \}}',
        f'{name} = {{ Model = "{model}", Texture = "{texture}" }}',
        text,
    )
    open(IDS_FILE, "w", encoding="utf-8").write(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument("--user")
    who.add_argument("--group")
    args = parser.parse_args()
    api_key = os.environ.get("ROBLOX_API_KEY")
    if not api_key:
        print("Set ROBLOX_API_KEY first (see tools/sfx/upload_audio.py).")
        return 1
    creator = {"userId": args.user} if args.user else {"groupId": args.group}

    for name, entry in read_entries().items():
        fbx = os.path.join(MODELS, f"{name}.fbx")
        png = os.path.join(MODELS, f"{name}_texture.png")
        if not os.path.exists(fbx):
            print(f"{name}: no {os.path.relpath(fbx, ROOT)}, skipped")
            continue
        model, texture = entry["Model"], entry["Texture"]
        try:
            if not texture and os.path.exists(png):
                try:
                    texture = "rbxassetid://" + upload_file(png, f"BHW {name} texture", "Image", "image/png", api_key, creator)
                except RuntimeError as e:
                    print(f"  {name}: Image upload refused ({e}); trying as a Decal")
                    texture = "decal:" + upload_file(png, f"BHW {name} texture", "Decal", "image/png", api_key, creator)
                write_entry(name, model, texture)
                print(f"  {name} texture: {texture}")
            if not model:
                model = "rbxassetid://" + upload_file(fbx, f"BHW {name}", "Model", "model/fbx", api_key, creator)
                write_entry(name, model, texture)
                print(f"  {name} model: {model}")
            else:
                print(f"  {name}: already uploaded ({model})")
        except RuntimeError as e:
            print(f"  {name}: FAILED - {e}")
    print("Done. Commit src/ReplicatedStorage/Shared/Assets/ModelIds.lua; the game loads them at startup.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
