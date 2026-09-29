# Research notes and roadmap

What the genre's biggest games and Roblox's own performance guidance say, what
this project already does about it, and what's worth building next. Written
September 2026.

## What the top games do (and what we took)

Steal a Brainrot and Grow a Garden both passed 20 million concurrent players
in 2025. They share "short, satisfying loops that fit into real life" plus
server-wide moments.

| Pattern | In the top games | Here |
|---|---|---|
| Buy characters off a moving conveyor | Steal a Brainrot's red carpet | Brainrot Parade (done) |
| Mutations that multiply value | Gold/Diamond/Rainbow variants | Mutations (done), night-only Galaxy |
| Random server-wide weather that buffs everyone | Grow a Garden weather events (e.g. "Restock Fever") | Coin Rain (done), **Lucky Rainbow (new)**: mutation chance x2 for 2.5 min, rainbow in the sky |
| Scheduled "admin abuse" events | Exclusive characters, big social moments | Not yet (see roadmap) |
| Shop restock timer | Grow a Garden restocks every 5 minutes | Parade spawns continuously; a timed "limited stock" shop is on the roadmap |
| Gifting | Hold an item, approach a player, gift prompt, accept/decline | Not yet (see roadmap) |
| Stealing | The main hook in Steal a Brainrot, and the most-reported source of children crying | **Deliberately left out** |

## Base biome (done this pass)

- The world had no edge, so you could walk off it. Now there's a ring of
  rolling hills plus an invisible wall at the edge, a grass skirt, and big
  horizon hills so the view is a valley, not void.
- Lily pond with a dock, lily pads and reeds in the north-west wilds.
- Meadow patches (light, dark and buttercup grass) break up the flat lawn.
- Fireflies at night, pollen by day (they follow the day/night cycle and
  switch off on low graphics quality).
- Drifting cartoon clouds (client-only, synced from server time).
- Ground plate lowered 0.05 studs so it no longer z-fights (flickers)
  against paths and zone floors.

## Optimization (Roblox guidance vs. this project)

From Roblox's performance docs (`performance-optimization/improve`) and the
instance streaming guide (`workspace/streaming/techniques`):

| Guidance | Status |
|---|---|
| Enable instance streaming for large worlds | **Done**: `StreamingEnabled`, `StreamOutBehavior = Opportunistic` (low-memory phones drop far content aggressively) |
| Keep `StreamingMinRadius` 64 / `StreamingTargetRadius` 1024 defaults | Kept |
| Client scripts must not assume world instances exist | Already true: every controller uses CollectionService added/removed signals or builds its own local models |
| `ModelStreamingMode.Atomic` for small logical groups | **Done**: each landscape prop is an Atomic Model |
| Avoid overusing `Persistent` | None used |
| `CanCollide/CanTouch/CanQuery = false` on non-interactive parts | Done (WorldKit defaults, Brainrot models, biome decor) |
| `CastShadow = false` on small/distant parts | Done for props, hills, clouds, rainbow |
| Fewer/shorter lights, lights without shadows | Decor lights off by day, never cast shadows |
| Visual effects created on the client | Parade, coins, wanderers, clouds and rainbow are all client-side |
| Don't run expensive work on Heartbeat | Wanderers at 30 Hz within 220 studs; sky at 10 Hz |
| Disconnect connections, clean tables | MovementController detaches on stream-out |
| `FallenPartsDestroyHeight` | Raised to -120 so anyone who falls respawns quickly |

## Map design pass (done)

- Paths: cream cobblestone instead of dark navy, with flower beds at every lamp.
- A dirt trail to the Lily Pond, plus a picnic spot.
- Two giant Gold/Diamond Brainrot statues as landmarks you can see from anywhere.

## Still to improve (found in the audit)

- **Dark UI palette in zones**: fixed for the Hub (spawn) with a new
  `WorldKit.Palette` (cream paving, rose/cream dais, lilac stone, wood deck).
  The Hatchery and Arena still use the dark Theme colours. That's defensible
  for an indoor hatchery and a neon team arena, but worth a look in Studio.
- **Onboarding**: done. A 3-step guide with a glowing trail (Hatchery, then
  first hatch, then Parade), a 250 Coin reward, and "Hatch" prompts on the
  egg podiums.
- **Audio has no asset ids yet** (`AudioConfig` cues are empty strings by
  design). Picking real sounds from the Creator Store is the biggest cheap
  win left for "feel".
- **No mobile playtest yet**: part count, streaming behaviour and UI scale
  need a real phone session in Studio's device emulator.

## Roadmap (not built yet)

Ranked by fun per effort for a young audience:

1. **Gifting**: give a Brainrot to a friend with a ProximityPrompt, and the
   friend accepts or declines. Needs a trade-safety cap (no Robux items, a
   cooldown, confirmation on both sides).
2. **Limited-stock egg shop** with a visible 5-minute restock countdown: a
   reason to come back, and a server-wide "restock!" moment.
3. **More weather**: "Starfall" at night (Galaxy mutation x3), "Golden Hour"
   at dusk (Gold x3). Same Workspace-attribute pattern as Lucky Rainbow.
4. **Weekend admin-style event**: a scheduled hour with an exclusive
   Brainrot only obtainable then (no FOMO pricing, free to everyone who's
   online).
5. **Brainrot fishing at the Lily Pond**: a tap-timing minigame that hatches
   a pond-themed egg.
6. **SLIM level of detail** (`Model.LevelOfDetail`) for zone models once they
   use MeshParts; today everything is basic parts, so there's nothing for
   SLIM to simplify yet.
7. **Terrain water** for the pond if we ever move off pure parts. Parts
   were kept on purpose: the whole map builds from code with no Studio
   editing.

## Sources

- [Steal a Brainrot (Wikipedia)](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- [Grow a Garden (Wikipedia)](https://en.wikipedia.org/wiki/Grow_a_Garden)
- [Cozy Chaos: why Grow a Garden and Steal a Brainrot work (Gameflip)](https://gameflip.com/en/blog/cozy-chaos-why-grow-a-garden-and-steal-a-brainrot-are-the-perfect-low-stress-games-right-now)
- [Grow a Garden weather events (Sportskeeda)](https://www.sportskeeda.com/roblox-news/grow-garden-weather-events-guide)
- [Grow a Garden mechanics: restock, gifting (Fandom)](https://growagarden.fandom.com/wiki/Mechanics)
- [Roblox docs: improve performance](https://github.com/Roblox/creator-docs/blob/main/content/en-us/performance-optimization/improve.md)
- [Roblox docs: streaming techniques](https://github.com/Roblox/creator-docs/blob/main/content/en-us/workspace/streaming/techniques.md)
- [DevForum: instance streaming best practices](https://devforum.roblox.com/t/instance-streaming-best-practices-and-techniques/4563685)
