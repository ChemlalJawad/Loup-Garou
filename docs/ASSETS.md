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
