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

Both `Main.server.lua` and `Main.client.lua` **auto-discover** every service/
controller/zone that follows the file's expected shape (an `Init()`/`Build()`
function) — adding a new system never requires editing a shared boot file.

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
