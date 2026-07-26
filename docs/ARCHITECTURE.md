# Architecture

**Brainrot Hatch Wars** is a [Rojo](https://rojo.space) project: all game
logic lives in this git repo as plain Luau text files, and Rojo syncs it
into Roblox Studio (two-way, no manual copy/paste). This doc is the map for
anyone (human or agent) adding a system.

## Getting it running

1. Install [Aftman](https://github.com/LPGhatguy/aftman) or the Rojo Studio
   plugin, and Rojo itself (`aftman install` if an `aftman.toml` is present,
   otherwise `cargo install rojo` / download from GitHub releases).
2. From the repo root: `rojo serve`.
3. In Roblox Studio, open the Rojo plugin and click **Connect**.
4. Press Play. The world, HUD, shop, eggs and CTF mode all boot from
   `src/ServerScriptService/Server/Main.server.lua` and
   `src/StarterPlayer/StarterPlayerScripts/Client/Main.client.lua`.

## Folder layout

```
src/
  ReplicatedStorage/Shared/     -- code + config used by BOTH client and server
    Constants.lua                -- game-wide constants, remote event names
    Theme.lua                    -- design tokens (color/font/spacing)
    Net.lua                      -- RemoteEvent/RemoteFunction accessor
    UIKit/                       -- reusable UI components (Button, Panel, ...)
    Eggs/                        -- EggConfig.lua (egg + brainrot pool defs)
    Shop/                        -- ShopConfig.lua (game passes + dev products)
    CTF/                         -- CTFConfig.lua (combat roster, team/map config)
  ServerScriptService/Server/
    Main.server.lua              -- boot: requires + Inits every service, in order
    Services/                    -- one file per system, server-authoritative
      DataService.lua            -- ALL player persistence goes through here
      EggService.lua
      ShopService.lua
      CTFService.lua
      TeamService.lua
    World/                       -- map/lighting generation scripts
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.lua              -- boot: requires + Inits every controller
    Controllers/                 -- one file per system, client-side
    UI/                          -- screen-building code (uses UIKit)
  StarterGui/
docs/                            -- architecture, design system, roster, marketing
```

## Conventions

- **PascalCase** for modules, services, controllers, and public functions/
  fields. **camelCase** for local variables. This matches the Roblox Lua
  style guide and keeps `require()`d modules reading like APIs.
- **`--!strict`** at the top of every module where practical, with exported
  `type` aliases for any table shape passed across a module boundary.
- **No external packages.** No Wally, no Rojo `sourcemap` dependents beyond
  Rojo itself. Everything must run from a bare `rojo serve` + Studio sync —
  don't add a build step.
- **Server is authoritative.** Clients only ever *request* (hatch an egg,
  join a team, use an ability); the server validates, mutates state via
  `DataService`, and pushes results back over a `RemoteEvent`. Never trust a
  client-sent price, rarity roll, or damage number.
- **One system, one file-set.** `EggService` never writes CTF state,
  `CTFService` never grants coins directly — it calls `DataService`. This is
  what let five people (well, five *agents*) build this in parallel without
  merge conflicts: touch your own service + controller + UI screen, read
  (don't rewrite) `Constants`, `Theme`, `Net`, `DataService`, and the shared
  `UIKit` components.
- **Remotes** are never created ad hoc. Add the name to
  `Constants.REMOTE_NAMES` under your domain, then call
  `Net.GetEvent(Constants.REMOTE_NAMES.YourDomain.YourAction)` from both
  sides. `Net` lazily creates the instance on the server and waits for it on
  the client, so there's no manual wiring in `ReplicatedStorage`.
- **Player data** always goes through `DataService`'s API
  (`AddCoins`, `TrySpendCoins`, `AddBrainrot`, `EquipBrainrot`,
  `SetGamePassOwned`, `IncrementStat`, ...) — never `SetAsync`/`GetAsync`
  directly from another service.
- **Monetization IDs are placeholders.** Game Pass and Developer Product ids
  in `ShopConfig.lua` are `0` until the game is published and real products
  are created in the Creator Dashboard — that step can't be done from code.
  Search for `-- TODO: set real id` when publishing.

## Data flow example (hatching an egg)

1. Client `EggController` fires `Egg_RequestHatch` with an egg id + hatch
   count (1/3/10).
2. Server `EggService` validates the egg id, checks & spends currency via
   `DataService.TrySpendCoins`/`TrySpendGems`, rolls rarity + species from
   `EggConfig`, grants each result via `DataService.AddBrainrot`.
3. Server fires `Egg_HatchResult` back to that client with the rolled
   results (for the reveal animation) and `Egg_InventoryUpdated` /
   `Shop_CurrencyUpdated` so the HUD refreshes.
4. Client `EggController` plays the hatch reveal UI from the result payload;
   it never rolls rarity itself.

Every other system (shop purchases, CTF ability use, flag capture) follows
the same request → validate → mutate `DataService` → broadcast result shape.
