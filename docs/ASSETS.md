# Assets: sounds, models, terrain

The game runs with **zero uploaded assets**. Everything below makes it
look and sound better, and every step is optional.

## 1. Sound effects and music (ready, just upload)

`assets/sfx/` holds **30 sound effects + 2 music loops**, one `.ogg` per cue
in `AudioConfig.lua` (`ChestOpen.ogg`, `HatchReveal_Secret.ogg`,
`Music_Hub.ogg`, ...). They are original and synthesized by
`tools/sfx/generate_sfx.py`, so there's no licence to worry about.
Re-run the script to regenerate them. Tweak a function there to change a sound.

Roblox only plays sounds that are uploaded to your account. There are two
ways to do that.

**A. Script (recommended)**: uploads and fills in the ids for you.

1. Creator Dashboard → Open Cloud → API Keys → Create API Key. Add the
   **Assets API** (read + write) and allow your IP.
2. From the repo root:

   ```bash
   # Windows PowerShell: $env:ROBLOX_API_KEY="..."
   export ROBLOX_API_KEY="..."
   python tools/sfx/upload_audio.py --user <your user id>
   ```

   Your user id is the number in `roblox.com/users/<id>/profile`. For a group
   game, use `--group <id>` instead.
3. The script writes the ids into
   `src/ReplicatedStorage/Shared/Audio/AudioIds.lua`. Rojo syncs that file,
   and the sounds play.

Roblox allows **10 audio uploads a month** without ID verification (100 with
it). By default the script uploads the 10 sounds players hear most (click,
coins, purchase, egg crack, the hatch reveals, chest, hub music). Run it
with `--all` once you're verified, or again next month; it skips anything
already uploaded.

**B. By hand**: in Studio, open View → Asset Manager → Bulk Import and pick
the `.ogg` files. Right-click each one, choose Copy Asset ID, and paste it
into `AudioIds.lua` as `"rbxassetid://<id>"`.

## 2. Realistic ground (automatic)

`TerrainZone.lua` builds the ground from Smooth Terrain:

- Grass with animated blades that sway in the wind.
- A real, swimmable water pond.
- Rolling terrain hills along the edge.
- Volumetric clouds.

Nothing to upload. If terrain generation ever fails, the old part-built ground
comes back automatically.

## 3. Your own Brainrot and egg models (drop-in)

Roblox's asset servers aren't reachable from the build environment, so no
Creator Store models are bundled. Using ids from there unchecked would be
risky anyway: stolen art, or scripts hidden in free models. Instead, the game
has **drop-in slots**:

```
ReplicatedStorage
└── AssetOverrides
    ├── Brainrots
    │   └── TralaleroAstrale   (a Model, named exactly like the brainrot id)
    └── Eggs
        └── BasicEgg           (BasicEgg / GoldenEgg / SecretEgg)
```

1. In Studio, insert a model (Toolbox, your own Blender `.fbx` via the 3D
   Importer, or a model a friend made for you).
2. Rename it to the id and drag it into the matching folder.
3. Save the place (File → Save). Rojo leaves these folders' contents alone,
   but only the place file stores them.

The model then replaces the built-in one everywhere: companions, the Parade,
the wandering Brainrots, the giant statues, the hatch reveal, the Hatchery
podiums. It is normalized automatically:

- **Scripts removed**: a free model can't run code in your game.
- **Resized** to the built-in model's height and set on the same ground line.
- **Same rules as the built-ins**: no collisions, a single shadow, welded
  for companions, rarity glow added on top.
- **Facing**: point the model's front toward −Z (Roblox's LookVector) before
  you drop it in.

Brainrot ids: see `EggConfig.SpeciesByRarity`, e.g. `PolpoMotorino`,
`GirafferroEspressone`, `FenicotteroPizzaiolo`, `CrocobrividoVulcanico`,
`TralaleroAstrale`.

**Licensing:** only use models you made, commissioned, or that the creator
clearly allows others to use. Many "brainrot" models on the Toolbox are
re-uploads of other people's art.

## 4. Recommended models (checked September 2026)

Licence, triangle count and scripts were checked on each page. Roblox's
**20,000-triangle limit per MeshPart** matters: anything above it must be
decimated in Blender first (Decimate modifier, ratio ≈ 0.5).

### Brainrots (Sketchfab, download as FBX)

| Model | Author | Licence | Tris | Use as |
|---|---|---|---|---|
| [Tralalero Tralala](https://sketchfab.com/3d-models/tralalero-tralala-091fffbf2972484f9c35c8a2ec8916f3) | Eks.Art | CC BY ✅ | 36.6k → decimate | `TralaleroAstrale` |
| [BOMBARDIRO CROCODILO](https://sketchfab.com/3d-models/bombardiro-crocodilo-db92444b3c064933a6f8ae31b0c27810) | Aizen | CC BY ✅ | 10k ✅ | `CrocobrividoVulcanico` |
| [Bombardino Crocodilo (game ready)](https://sketchfab.com/3d-models/bombardino-crocodilo-game-ready-3d-model-free-82de12bb94e948e188dbe1a4dc83dceb) | Alex CGW | CC BY ✅ | 25k → decimate | alternative `CrocobrividoVulcanico` |
| [Tung Tung Tung Sahur](https://sketchfab.com/3d-models/tung-tung-tung-sahur-91ddd9079bd84019ba4a12e01d93a0d6) | Eks.Art | CC BY ✅ | 35.8k → decimate | a future species |
| [Tralalero Tralala (game ready)](https://sketchfab.com/3d-models/tralalero-tralala-3d-game-ready-model-free-e043ac3561f9417b800b6cd04a0de163) | Alex CGW | **CC BY-NC ❌** | 16.8k | don't use (non-commercial, and the shoes are Nike-branded) |

More (licences not yet checked, check each page): the collection
[Italian Brainrot by e.ticoalu](https://sketchfab.com/e.ticoalu/collections/italian-brainrot-5494c32e88054a3aa52b097f0c3b2139)
(Boneca Ambalabu, Brr Brr Patapim, Chimpanzini Bananini, Bobrito Bandito,
Capuchino Assasino, Balerina Capuchino...).

**CC BY = you must credit the author.** Put a line in the game description,
for example "3D models: Eks.Art, Aizen (CC BY 4.0, Sketchfab)". Avoid any
**NC** (NonCommercial) model: the game sells Robux items.

**Download them in one command** (licence-checked, refuses NC/ND, writes the
credits file). Needs your Sketchfab API token (Settings → Password & API):

```bash
export SKETCHFAB_TOKEN=...        # Windows PowerShell: $env:SKETCHFAB_TOKEN="..."
python tools/models/download_models.py
```

Files land in `assets/models/` (git-ignored) with `CREDITS.txt`.

Importing: in Studio, Avatar/Home tab → **Import 3D**, pick the FBX, then
drag the resulting Model into `ReplicatedStorage/AssetOverrides/Brainrots`
and rename it.

### Eggs (Roblox Creator Store, free)

| Model | Creator | Rating | Scripts | Use as |
|---|---|---|---|---|
| [Egg mesh](https://create.roblox.com/store/asset/5168800671/Egg-mesh) | @francherre | 96% (200+ votes) | none ✅ | all three eggs: recolour it (gold for `GoldenEgg`, dark/neon for `SecretEgg`) |
| [Egg Pets KIT](https://create.roblox.com/store/asset/15850322685/Egg-Pets-KIT) | @Rrg_125 | 87% (100+ votes) | **has scripts** ⚠️ | take the egg models only; the drop-in slot strips the scripts, but don't put the kit itself in the game |

Fastest way to get the Egg mesh: paste this into Studio's **Command Bar**
(View → Command Bar) and press Enter. It inserts the free model into
`AssetOverrides/Eggs` for all three eggs:

```lua
local eggs = game.ReplicatedStorage.AssetOverrides.Eggs; for name, color in { BasicEgg = Color3.fromRGB(245, 240, 225), GoldenEgg = Color3.fromRGB(255, 200, 60), SecretEgg = Color3.fromRGB(120, 60, 200) } do local m = game:GetService("InsertService"):LoadAsset(5168800671); local egg = m:FindFirstChildWhichIsA("Model") or m; egg.Name = name; for _, p in egg:GetDescendants() do if p:IsA("BasePart") then p.Color = color end end; egg.Parent = eggs; if egg ~= m then m:Destroy() end end
```

Then save the place (Ctrl+S).

Not individually checked: [Golden Egg](https://create.roblox.com/store/asset/14042411629/Golden-Egg),
[Dragon Egg](https://create.roblox.com/store/asset/380074338/Dragon-Egg),
[Black Hole Egg](https://create.roblox.com/store/asset/14551504460/Black-Hole-Egg).
Before using them, open each one in Studio and look for Scripts.
