# Brainrot Hatch Wars

A Roblox game: hatch Eggs to collect original "Brainrot" characters, equip
one for its unique ability, then take it into **Brain-Rot Capture the
Flag** — a two-team objective mode — while a Robux shop sells premium
currency and permanent perks. Built as a [Rojo](https://rojo.space) project:
everything is plain Luau text in this repo, synced into Roblox Studio with
no manual copy/paste and no build step.

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

## The loop

**Hatch** (Basic/Golden/Secret Eggs, Coins or Gems) → **collect** one of 16
original Brainrot characters across 5 rarities → **equip** one for its CTF
ability → **battle** in Brain-Rot Capture the Flag (Team Ember vs. Team
Frost) → earn Coins from captures/tags/returns → hatch more. The Robux shop
sells Gems/Coins top-ups and permanent Game Passes (VIP, Double Coins,
Double Luck, +50 inventory slots) that feed back into the same loop.

## How this was built

Five specialists worked this codebase in parallel, each owning a disjoint
slice of files against a shared architecture (`Constants`, `Net`,
`DataService`, `Theme`, `UIKit`, `Shell`) fixed up front so nothing
conflicted: a systems programmer for the egg economy, a monetization
programmer for the Robux shop, a gameplay/PvP programmer for the CTF mode,
an environment/UX designer for the world and HUD polish, and a marketing
strategist for positioning and launch. See `docs/ARCHITECTURE.md` for the
conventions that made that possible, and each doc's own notes for what's
still a placeholder (monetization ids, Theme.lua "v2" suggestions) versus
what's actually load-bearing.
