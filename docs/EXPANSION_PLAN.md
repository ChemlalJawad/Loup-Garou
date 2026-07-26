# Expansion Plan — Ownership Matrix

This document is the coordination contract for the v2 build-out. Fifteen
specialists work this repo concurrently, so **every file has exactly one
owner**. If a file isn't in your row, you may `require` and read it, but you
must not edit it.

Read this together with [`ARCHITECTURE.md`](ARCHITECTURE.md) (conventions,
data flow) and [`BRAINROT_ROSTER.md`](BRAINROT_ROSTER.md) (canonical
character ids).

## Shared foundations — READ-ONLY for everyone

These were extended before the parallel work started, specifically so nobody
needs to edit them. If you genuinely need something added here, note it in
your final summary instead of editing.

| File | What it gives you |
|---|---|
| `Shared/Constants.lua` | Remote names (`REMOTE_NAMES.<Domain>.<Action>`), tuning numbers, team defs, reward tables, rarity/sell/merge values |
| `Shared/Theme.lua` | Design tokens: colors, `Theme.RarityColor(rarity)`, fonts, spacing, corner radii, motion timings |
| `Shared/Net.lua` | `Net.GetEvent(name)` / `Net.GetFunction(name)` — lazily creates server-side, waits client-side |
| `Shared/UIKit/` | `Button, Panel, CurrencyPill, RarityBadge, Toast, Divider, Modal, TabBar, ScrollGrid, ProgressBar, ItemCard, Util` |
| `Shared/WorldLayout.lua` | The spatial allocation contract — each zone's exclusive rectangle |
| `Services/DataService.lua` | All persistence. Includes `Mutate(player, fn)` as the generic extension point |
| `Services/EconomyService.lua` | **All earned currency/XP flows through here** |
| `Client/UI/Shell.lua` | HUD shell: nav dock, panel registry, currency/level display, toasts |
| `World/WorldKit.lua` | Part-building primitives: `Part, Wedge, Sphere, Pillar, Stairs, Wall, Railing, TiledFloor, UprightCylinder, NeonBorder, Sign, SurfaceLabel, Spawn, Light, Emitter, Group` |
| `World/MapBuilder.lua` | Auto-discovers zones; do not edit |
| `Main.server.lua` / `Main.client.lua` | Auto-discover services/controllers; do not edit |

### The three rules that prevent most conflicts

1. **Earned currency goes through `EconomyService`**, never
   `DataService.AddCoins`. `EconomyService.AwardCoins(player, amount, reason)`
   applies the Double Coins pass, rebirth bonus and timed boosts.
   `DataService.AddCoins` remains correct *only* for Robux-purchased currency,
   which must not be multiplied.
2. **New persisted state uses `DataService.Mutate(player, function(profile) ... end)`.**
   The `Profile` type already has fields reserved for every system below
   (`Quests`, `Daily`, `CodesRedeemed`, `Boosts`, `Upgrades`, `Index`,
   `Level`, `XP`, `Rebirths`, `AutoHatch`). Touch only your own slice.
3. **UI panels register with the Shell.** Build your screen with
   `UIKit.Modal.new{...}`, parent `modal.Root` to `Shell.GetScreenGui()`, then
   `Shell.RegisterNavButton{ Id=..., Label=..., IconText=..., Panel=modal.Root, Order=..., OnClick=... }`.
   Shell then guarantees only one panel is open at a time. Never track your
   own `visible` boolean.

## Nav dock order

To keep the icon dock in a deliberate order rather than registration order,
each system passes a fixed `Order`:

| Order | System | Icon |
|---|---|---|
| 10 | Eggs | 🥚 |
| 20 | Index | 📖 |
| 30 | Store (in-game currency) | 🛒 |
| 40 | Shop (Robux) | 💎 |
| 50 | Quests | 📋 |
| 60 | Daily | 🎁 |
| 70 | Codes | 🎟️ |
| 80 | Leaderboards | 🏆 |
| 90 | Rebirth | ♻️ |
| 100 | Play CTF | ⚔️ |

## Ownership matrix

### Gameplay & systems

| # | System | Owns |
|---|---|---|
| 1 | **In-game Store** (the shop that works today) | `Shared/Store/StoreConfig.lua`, `Services/StoreService.lua`, `Controllers/StoreController.lua`, `UI/StoreUI.lua` |
| 2 | **Robux shop hardening** | `Shared/Shop/ShopConfig.lua`, `Services/ShopService.lua`, `Controllers/ShopController.lua`, `UI/ShopUI.lua` |
| 3 | **Egg system v2** | `Shared/Eggs/EggConfig.lua`, `Services/EggService.lua`, `Controllers/EggController.lua`, `UI/EggUI.lua` |
| 4 | **Brainrot companions (3D)** | `Shared/Brainrots/BrainrotModels.lua`, `Services/PetService.lua`, `Controllers/PetController.lua` |
| 5 | **Collection index** | `Shared/Index/IndexConfig.lua`, `Services/IndexService.lua`, `Controllers/IndexController.lua`, `UI/IndexUI.lua` |
| 6 | **Quests** | `Shared/Quests/QuestConfig.lua`, `Services/QuestService.lua`, `Controllers/QuestController.lua`, `UI/QuestUI.lua` |
| 7 | **Daily rewards + promo codes** | `Shared/Daily/DailyConfig.lua`, `Shared/Codes/CodesConfig.lua`, `Services/DailyRewardService.lua`, `Services/CodesService.lua`, `Controllers/DailyController.lua`, `UI/DailyUI.lua`, `UI/CodesUI.lua` |
| 8 | **Idle income + economy HUD** | `Services/IdleIncomeService.lua`, `Controllers/EconomyController.lua`, `UI/RebirthUI.lua`, `UI/RewardPopup.lua` |
| 9 | **Leaderboards** | `Services/LeaderboardService.lua`, `Controllers/LeaderboardController.lua`, `UI/LeaderboardUI.lua` |
| 10 | **CTF v2** | `Shared/CTF/CTFConfig.lua`, `Services/CTFService.lua`, `Services/TeamService.lua`, `Controllers/CTFController.lua`, `UI/CTFHud.lua` |
| 11 | **Audio + VFX juice** | `Shared/Audio/AudioConfig.lua`, `Shared/Effects/FX.lua`, `Services/AudioService.lua`, `Controllers/AudioController.lua` |

### World design

Each zone module lives in `World/`, is named `<Something>Zone.lua`, returns
`{ Order: number?, Build: (parent: Instance) -> () }`, and is auto-discovered
by `MapBuilder`. **All geometry must stay inside the zone's rectangle from
`WorldLayout.lua`.**

| # | Zone(s) | Owns | Rect centre |
|---|---|---|---|
| 12 | Central plaza | `World/HubZone.lua` | `(0, 0)` 150×150 |
| 13 | Hatchery + market district | `World/HatcheryZone.lua`, `World/CommercialZone.lua` | `(0, -200)`, `(210, 0)` |
| 14 | CTF arena | `World/ArenaZone.lua` | `(0, 300)` 260×320 |
| 15 | Hall of Fame + VIP lounge + lighting | `World/PlazaZone.lua`, `World/LoungeZone.lua`, `World/LightingSetup.lua` | `(-210, 0)`, `(210, -200)` |

## Cross-system contracts (named parts / named perks)

These are the only places two systems touch, and they touch by **name**, never
by direct require:

| Contract | Producer | Consumer |
|---|---|---|
| `RedBaseSpawn`, `BlueBaseSpawn`, `RedFlagStand`, `BlueFlagStand` (part names, found via recursive `Workspace:FindFirstChild(name, true)`) | Zone 14 (Arena) | CTF v2 (#10) |
| `LeaderboardStand1` … `LeaderboardStand4` (anchored parts to attach SurfaceGuis to) | Zone 15 (Plaza) | Leaderboards (#9) |
| Perk flags `"DoubleCoins"`, `"DoubleLuck"` via `DataService.SetPerk/GetPerk` | Robux shop (#2) | EconomyService, Eggs (#3) |
| Boost names `EconomyService.BOOST_COINS_2X / BOOST_XP_2X / BOOST_LUCK_2X` via `DataService.GrantBoost` | Store (#1), Daily (#7), Codes (#7) | EconomyService, Eggs (#3) |
| `Constants.REMOTE_NAMES.Shared.Notify` → toast | any server system | already wired globally in `Main.client.lua` |
| `Constants.REMOTE_NAMES.Audio.PlaySfx` → sound cue by id | any server system | Audio (#11) |

## Verification

There is no Roblox Studio in the build sandbox, so nothing can be
play-tested here. Every file is syntax-checked against a real Luau parser
before merge. Write defensively: `pcall` around anything touching
DataStores or `MarketplaceService`, `FindFirstChild` rather than direct
indexing for world parts, and never assume another system's parts exist yet.
