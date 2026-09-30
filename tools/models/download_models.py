#!/usr/bin/env python3
"""Downloads the recommended Brainrot models from Sketchfab (docs/ASSETS.md).

Standard library only. For each model it:
  * reads the licence from Sketchfab's API and REFUSES anything
    non-commercial (NC) or no-derivatives (ND) - the game sells Robux items;
  * downloads the .glb (Roblox Studio's 3D Importer opens .glb directly),
    falling back to the glTF zip;
  * saves it as assets/models/<GameId>.glb and appends the required CC BY
    credit to assets/models/CREDITS.txt.

Setup: sketchfab.com -> Settings -> Password & API -> copy your API token.

  set SKETCHFAB_TOKEN=...          (Windows)   /   export SKETCHFAB_TOKEN=...
  python tools/models/download_models.py
  python tools/models/download_models.py --list        # just show the plan
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models")
API = "https://api.sketchfab.com/v3"

# Game id -> Sketchfab model uid. Keep in sync with docs/ASSETS.md.
MODELS = {
    "CrocobrividoVulcanico": "db92444b3c064933a6f8ae31b0c27810",  # Bombardiro Crocodilo - Aizen, 10k tris
    "TralaleroAstrale": "091fffbf2972484f9c35c8a2ec8916f3",  # Tralalero Tralala - Eks.Art, 36.6k tris
    "TungTungSahur": "91ddd9079bd84019ba4a12e01d93a0d6",  # Tung Tung Tung Sahur - Eks.Art, 35.8k tris (future species)
}

TRIANGLE_LIMIT = 20000  # per MeshPart in Roblox


def get_json(url: str, token: str | None) -> dict:
    req = urllib.request.Request(url)
    if token:
        req.add_header("Authorization", f"Token {token}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} for {url}: {e.read().decode('utf-8', 'replace')[:300]}") from None


def download(url: str, path: str) -> None:
    with urllib.request.urlopen(url, timeout=300) as resp, open(path, "wb") as f:
        while chunk := resp.read(1 << 16):
            f.write(chunk)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="show licences and sizes without downloading")
    args = parser.parse_args()

    token = os.environ.get("SKETCHFAB_TOKEN")
    if not token and not args.list:
        print("Set SKETCHFAB_TOKEN first (sketchfab.com -> Settings -> Password & API).")
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    credits_path = os.path.join(OUT_DIR, "CREDITS.txt")

    for game_id, uid in MODELS.items():
        info = get_json(f"{API}/models/{uid}", None)
        licence = info.get("license") or {}
        label = licence.get("label") or licence.get("slug") or "unknown"
        slug = (licence.get("slug") or "").lower()
        author = (info.get("user") or {}).get("displayName") or (info.get("user") or {}).get("username") or "?"
        tris = info.get("faceCount") or 0
        print(f"{game_id:24s} '{info.get('name')}' by {author} - {label}, {tris} tris")

        if "nc" in slug.split("-") or "nd" in slug.split("-") or "NonCommercial" in label or "NoDerivs" in label:
            print("   SKIPPED: licence doesn't allow use in a monetized game / modification.")
            continue
        if not info.get("isDownloadable", True):
            print("   SKIPPED: not downloadable.")
            continue
        if tris > TRIANGLE_LIMIT:
            print(f"   NOTE: over Roblox's {TRIANGLE_LIMIT}-triangle mesh limit - decimate in Blender before importing.")
        if args.list:
            continue

        links = get_json(f"{API}/models/{uid}/download", token)
        if "glb" in links:
            target, url = os.path.join(OUT_DIR, f"{game_id}.glb"), links["glb"]["url"]
        elif "gltf" in links:
            target, url = os.path.join(OUT_DIR, f"{game_id}_gltf.zip"), links["gltf"]["url"]
        else:
            print(f"   SKIPPED: no glb/gltf download offered ({', '.join(links)}).")
            continue
        download(url, target)
        print(f"   saved {os.path.relpath(target, ROOT)} ({os.path.getsize(target) // 1024} KB)")
        with open(credits_path, "a", encoding="utf-8") as f:
            f.write(f"{game_id}: \"{info.get('name')}\" by {author} ({label}) - https://sketchfab.com/3d-models/{uid}\n")

    if not args.list:
        print(f"\nCredits to paste into the game description: {os.path.relpath(credits_path, ROOT)}")
        print("Next: Studio -> Import 3D -> pick the .glb -> rename to the game id ->")
        print("      drag into ReplicatedStorage/AssetOverrides/Brainrots -> save the place.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
