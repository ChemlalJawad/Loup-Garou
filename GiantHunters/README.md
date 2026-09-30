# Giant Hunters

A grapple-rig action game for Roblox: swing through a walled old town on two
cable hooks and take down wandering giants by slashing the glowing weak
spot on the back of their neck. It's inspired by the "titan-slaying" genre,
with an original setting and names, and it's child-friendly: no gore, and
defeated giants puff away into steam.

This is a separate Rojo project from Brainrot Hatch Wars, in the same repo.

## Run it

```bash
cd GiantHunters
rojo serve
```

In Studio, open a new **Baseplate** and delete the `Baseplate` and
`SpawnLocation` parts. Then **Plugins → Rojo → Connect** and press **Play**.
The map, the giants and the HUD all build themselves.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Left / right hook (hold) | Q / E | L1 / R1 | "L Hook" / "R Hook" |
| Gas boost (in the air) | Space or Shift | A | "Gas" |
| Slash | Click or F | X | "Slash" |
| Resupply gas & blades | stand at a crate with a blue beam | | |

Shift-lock (camera lock) makes aiming easier: the crosshair turns green
when a hook would land.

## How it plays

- **Waves**: giants (Small / Medium / Colossal) walk in from the walls.
  Each wave is bigger, and clearing it starts a 15 s break.
- **Reach**: giants chase the nearest hunter they can reach. On a rooftop,
  up a tower or in the giant trees of the east forest, you're safe.
- **Grabs**: a giant in reach raises its arms (the warning). Still there
  0.8 s later? You're caught and respawn at the plaza.
- **Weak spot**: only the glowing patch on the back of the neck can be hurt.
  Hit it going fast (35+ studs/s) for a **clean cut**, which does full
  damage. Slow hits do half.
- **Blades**: 8 blades per life. One is used per hit. Resupply at a crate.
- **Gas**: used while hooked and while boosting. Refills slowly on the
  ground, or fully at a crate.
- **Scores**: the leaderboard shows Giants and Points
  (Small 1, Medium 2, Colossal 4).

## Code map

| File | What |
|---|---|
| `src/shared/Config.lua` | every tuning number (grapple forces, gas, giant sizes, waves) |
| `src/server/MapBuilder.lua` | walled town, towers, forest, supply crates, spawn |
| `src/server/GiantFactory.lua` | part-built giant rig (Motor6D limbs, glowing nape, kinematic mover) |
| `src/server/GiantService.lua` | giant AI, grabs, weak-spot damage, steam defeat, wave loop |
| `src/server/HunterService.lua` | leaderstats, blades, resupply, server-side slash validation |
| `src/client/GrappleController.lua` | hooks, cables, gas boost, slash input (client-simulated movement) |
| `src/client/Hud.lua` | crosshair, gas/blades, wave banner, toasts, "Caught!" screen |
| `src/client/GiantAnimator.lua` | client-only walk cycle and grab pose |

Movement runs on each player's own client, so the grapple feels instant.
Damage is always validated by the server (cooldown, blades left, real
distance to the nape).
