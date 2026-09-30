# Brainrot Hatch Wars

A Roblox game: hatch Eggs to collect original "Brainrot" characters (now
visible, procedurally-built companions that follow you), equip one for its
unique ability, then take it into **Brain-Rot Capture the Flag** — a
two-team objective mode with powerups, a kill feed and a results/MVP screen
— while progression systems (quests, daily rewards, promo codes, a
collection index, rebirth, global leaderboards) give you a reason to come
back. Two currency stores: an in-game-currency **Store** that works today,
and a **Robux Shop** that's wired for real money the moment the game is
published. Built as a [Rojo](https://rojo.space) project: everything is
plain Luau text in this repo, synced into Roblox Studio with no manual
copy/paste and no build step.

## Running it

1. Install [Rojo](https://rojo.space/docs/installation/) (via
   [Aftman](https://github.com/LPGhatguy/aftman), Cargo, or a release
   binary) and the matching Rojo Studio plugin.
2. From the repo root: `rojo serve`.
3. In Roblox Studio, open the Rojo plugin panel and click **Connect**.
4. Press Play. The world, HUD, egg hatchery, shop and CTF mode all boot
   automatically from `Main.server.lua` / `Main.client.lua`.

Before publishing for real: every Game Pass / Developer Product `Id` in
`ShopConfig.lua` is a placeholder `0` (Roblox only issues real ids for a
published place, via the Creator Dashboard — that step can't be done from
code). Search the repo for `-- TODO: set real id` when you're ready to wire
up real monetization.

## What's here

| Area | Docs |
|---|---|
| Folder layout, conventions, data flow | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Visual design system, world layout | [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) |
| The 16-character Brainrot roster (canonical) | [`docs/BRAINROT_ROSTER.md`](docs/BRAINROT_ROSTER.md) |
| Store page, monetization, launch plan | [`docs/MARKETING.md`](docs/MARKETING.md) |
| v2 ownership matrix / cross-system contracts | [`docs/EXPANSION_PLAN.md`](docs/EXPANSION_PLAN.md) |

## The loop

**Hatch** (Basic/Golden/Secret Eggs, Coins or Gems) → **collect** one of 16
original Brainrot characters across 5 rarities → **equip** one — it becomes
a visible companion that follows you and grants a CTF ability — → **battle**
in Brain-Rot Capture the Flag (Team Ember vs. Team Frost) → earn Coins and
XP from captures/tags/returns/round wins → **sell duplicates or merge** them
up a rarity tier → hatch more. Outside of matches, your equipped Brainrot
earns passive Coins by rarity; **quests**, **daily login rewards**, **promo
codes** and the **collection index** all pay into the same economy, which
**rebirth** lets you prestige into a permanent multiplier. Two places to
spend/earn currency: the in-game **Store** (upgrades, timed boosts,
consumables — Coins/Gems, works today) and the Robux **Shop** (Game Passes,
Gem/Coin packs — wired for real money, Studio-testable via an automatic test
mode until real ids are set).

Between those, the **Brainrot Parade** is a red carpet where Brainrots walk
past and can be bought before they reach the exit — the only source of
**mutations** (Gold x1.25, Diamond x1.5, Rainbow x10, and a night-only Galaxy
x4), which boost idle income. A **day/night cycle** makes nights the time to
hunt rare mutations; a **Coin Rain** event floods the Central Plaza every few
minutes; and the **Fun Park** has trampolines, jump pads, an obby tower and an
ice slide, with treasure chests at the top and hidden around the map.

## Systems

| System | Files |
|---|---|
| Player data / persistence | `Services/DataService.lua` |
| Reward funnel (multipliers, level/XP, rebirth) | `Services/EconomyService.lua` |
| Egg hatching, selling, merging, auto-hatch | `Shared/Eggs`, `Services/EggService.lua` |
| Visible Brainrot companions | `Shared/Brainrots`, `Services/PetService.lua` |
| Collection index + milestones | `Shared/Index`, `Services/IndexService.lua` |
| Quests (daily/weekly) | `Shared/Quests`, `Services/QuestService.lua` |
| Daily login rewards + promo codes | `Shared/Daily`, `Shared/Codes`, `Services/DailyRewardService.lua`, `Services/CodesService.lua` |
| Idle income, reward popups, rebirth UI | `Services/IdleIncomeService.lua`, `Controllers/EconomyController.lua` |
| Global leaderboards + physical stands | `Services/LeaderboardService.lua` |
| In-game currency store | `Shared/Store`, `Services/StoreService.lua` |
| Robux shop | `Shared/Shop`, `Services/ShopService.lua` |
| Capture the Flag (teams, flags, abilities, powerups, match flow) | `Shared/CTF`, `Services/CTFService.lua`, `Services/TeamService.lua` |
| Audio cues + juice effects | `Shared/Audio`, `Shared/Effects`, `Services/AudioService.lua` |
| World (auto-discovered zones) | `World/*Zone.lua`, `World/MapBuilder.lua`, `World/WorldKit.lua` |
| Brainrot Parade (red carpet shop, mutations) | `Shared/Parade`, `Shared/Brainrots/Mutations.lua`, `Services/ParadeService.lua`, `Controllers/ParadeController.lua` |
| Day/night cycle, zone moods, mobile quality scaling | `Shared/LightingConfig.lua`, `World/LightingSetup.lua`, `Controllers/LightingController.lua` |
| Fun Park: jump pads, trampolines, reward chests | `World/FunParkZone.lua`, `Controllers/MovementController.lua`, `Services/RewardChestService.lua` |
| Coin Rain world event | `Shared/Events`, `Services/EventService.lua`, `Controllers/EventController.lua` |
| Landscaping + hidden wild chests | `World/LandscapeZone.lua`, `World/PathRegistry.lua`, `WorldKit` props (Tree, Bush, FlowerBed, Rock, BalloonCluster, Mushroom) |
| Ambient wandering Brainrots (tap to pet) | `Controllers/AmbientLifeController.lua` |
| Base biome: edge hills + boundary, horizon, lily pond + trail, giant statues, meadows, fireflies | `World/BiomeZone.lua`, `WorldLayout.Landmarks` |
| Sky: drifting clouds, Lucky Rainbow arc | `Controllers/SkyController.lua` |
| Smooth Terrain ground (wind-swept grass, water pond, hills, clouds) | `World/TerrainZone.lua` |
| Original SFX + music, upload script | `assets/sfx/`, `tools/sfx/`, `Shared/Audio/AudioIds.lua` (see `docs/ASSETS.md`) |
| Themed wilds: Candy Land, Crystal Grove, Tulip Fields + windmill, rock outcrops, volcano & snowy-mountain backdrops (plan: `docs/map-plan.png`) | `World/WildsZone.lua`, `Controllers/SpinnerController.lua` |
| Uploaded Brainrot models, auto-loaded at server start | `tools/models/upload_models.py`, `Shared/Assets/ModelIds.lua`, `Services/ModelAssetService.lua` |
| Drop-in Brainrot/egg models | `ReplicatedStorage.AssetOverrides` (see `docs/ASSETS.md`) |
| New-player guide (3 steps, glowing trail, reward) | `Shared/Tutorial`, `Services/TutorialService.lua`, `Controllers/TutorialController.lua` |
| Lucky Rainbow weather (Parade mutation chance x2) | `Shared/Events/EventConfig.lua`, `Services/EventService.lua` |

Both `Main.server.lua` and `Main.client.lua` **auto-discover** every service/
controller/zone that follows the file's expected shape (an `Init()`/`Build()`
function) — adding a new system never requires editing a shared boot file.

## Designed for young players

The fun pass borrowed what works in the genre's most-played games (a red
carpet of Brainrots to buy, mutations, scheduled world events, a playground
to mess around in) and deliberately left out what doesn't work for kids:

- **No stealing.** In the biggest brainrot game, having a Brainrot stolen by
  another player is the most-documented source of upset children. Here the
  only competition is being first to buy from the Parade; nothing you own
  can be taken.
- **Rare things are protected.** "Sell duplicates" never sells a mutated
  Brainrot, and merges never consume one; selling one is always a single,
  confirmed action with a warning.
- **Everyone gets something.** Coin Rain is skill-free and shared, chests
  refill on a timer, and rewards scale with level so nobody is priced out.
- **Readable by default.** Daytime is the default and lasts 70% of the cycle;
  prompts are instant taps, not holds; info boards at the Parade explain
  prices and mutations before anyone has to ask.
- **Built for phones.** Everything that moves every frame (Parade walkers,
  coins, the day/night cycle) is animated on the client from shared server
  time, so it costs no network traffic; decorative lights and particles
  switch off on low graphics quality.
- **Nobody is lost in their first minute.** A three-step guide (walk to the
  Hatchery, hatch your first egg, visit the Parade) draws a glowing trail from
  your feet to the goal, with a bouncing marker and a distance counter, and
  pays 250 Coins at the end. The egg podiums themselves have a "Hatch"
  prompt. Skippable, and returning players who've already hatched never see it.
- **Something to discover everywhere.** The grass between zones is a park
  (~190 trees, bushes, flower beds, rocks, balloons, giant mushrooms) with
  three hidden chests out in the wilds, and Brainrots wander the lawns
  around the plaza - walk up and tap "Pet" for a hop and a burst of hearts.
  Petting gives no reward on purpose: nothing to farm, just friendly.

### Optimization notes

- `WorldKit.TiledFloor` draws one collision slab plus only the contrasting
  tiles as thin non-colliding overlays: half the parts, and one collider
  instead of hundreds (~400 parts saved map-wide, which pays for the whole
  landscape).
- Decorative parts that don't collide also skip raycasts (`CanQuery=false`)
  and touch events; Brainrot model parts never fire `Touched`, and only
  their root casts a shadow.
- Sign billboards stop rendering beyond 220 studs.
- Ambient wanderers are client-only, update at 30 Hz, and freeze when more
  than 220 studs from the player.
- Instance streaming is on (`StreamOutBehavior = Opportunistic`), and every
  landscape prop is an Atomic Model. See `docs/RESEARCH_ROADMAP.md` for the
  full checklist against Roblox's performance guidance, plus the roadmap.

## How this was built

The base game (egg economy, Robux shop, CTF, world, HUD, marketing) was
built by five specialists working in parallel. A second wave of fifteen
specialists then expanded it — a working in-game store, a hardened Robux
path with a Studio test mode, visible 3D companions, quests, daily
rewards/codes, idle income, leaderboards, a deeper CTF mode, audio/VFX, and
four new world zones — each owning a disjoint slice of files against a
shared architecture (`Constants`, `Net`, `DataService`, `EconomyService`,
`Theme`, `UIKit`, `Shell`, `WorldKit`, `WorldLayout`) fixed up front so nothing
conflicted. See `docs/ARCHITECTURE.md` and `docs/EXPANSION_PLAN.md` for the
conventions that made that possible. Every file in the repo is verified
against a real Luau parser before being committed — there is no Roblox
Studio available in this build environment, so that parser check (not a
Play-test) is the correctness gate; a manual Studio pass is still recommended
before shipping.
