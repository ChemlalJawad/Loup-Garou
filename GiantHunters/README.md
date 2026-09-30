# Giant Hunters

A grapple-rig action game for Roblox: swing through a walled old town on two
cable hooks and take down wandering giants by slashing the glowing weak
spot on the back of their neck. It's inspired by the "titan-slaying" genre,
with an original setting and names, and it's child-friendly: no gore, and
defeated giants puff away into steam.

This is a separate Rojo project from Brainrot Hatch Wars, in the same repo.

![Giants and a hunter with twin swords](giants-preview.jpg)

*Offline preview, rendered outside Roblox from the same part-building code
(so the lighting isn't Roblox's). Not a Studio screenshot.*

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
| Left / right hook (hold, then swing) | Q / E | L1 / R1 | "L Hook" / "R Hook" |
| Reel in (hooked) / gas boost (in the air) | hold Space | A | "Gas" |
| Gas dash | Shift | B | "Dash" |
| Slash with both blades (a full spin in the air) | Click or F | X | "Slash" |
| Resupply gas & blades | stand at a crate with a blue beam | | |

Shift-lock (camera lock) makes aiming easier: the crosshair turns green
when a hook would land.

### The grapple, like the anime's gear

- A hook **flies** to what you aim at, then bites. The cable stays taut
  (it winds in any slack), so gravity swings you round the anchor like a
  pendulum. Let go at the bottom of the swing to fling yourself forward.
- Hook both sides at once to swing between two anchors.
- Hold Space while hooked to **reel in** hard (uses gas): that's how you
  zip up a giant's back to its neck.
- Hooks can bite giants too, and move with them.
- In the air you steer with WASD, face where you fly and lean into dives.
  A slash in the air is a full spin with blade trails.
- Gas shows as white jets behind you. The view widens with speed.
- Other hunters see your cables.

## How it plays

- **Waves**: giants (Small / Medium / Colossal) walk in from the walls.
  Each wave is bigger, and clearing it starts a 15 s break.
- **Reach**: giants chase the nearest hunter they can reach. On a rooftop,
  up a tower or in the giant trees of the east forest, you're safe.
- **Grabs**: a giant in reach raises its arms (the warning). Still there
  0.8 s later? You're caught and respawn at the plaza.
- **Giants**: part-built, soft and rounded, with a hunched walk, a wide
  toothy grin and eyes that follow you. Four body types (lanky, stocky,
  chubby, bighead) and random skin, hair and shorts, so no two look alike.
- **Weak spot**: only the glowing lump on the back of the neck can be hurt.
  Hit it going fast (35+ studs/s) for a **clean cut**, which does full
  damage. Slow hits do half.
- **Blades**: a sword in each hand, 8 blades per life. One is used per
  hit. With none left they turn dull and grey. Resupply at a crate.
- **Gas**: used to reel in, boost and dash. Refills slowly on the ground,
  or fully at a crate.
- **Scores**: the leaderboard shows Giants and Points
  (Small 1, Medium 2, Colossal 4).

## Code map

| File | What |
|---|---|
| `src/shared/Config.lua` | every tuning number (grapple forces, gas, giant sizes, waves) |
| `src/server/MapBuilder.lua` | walled town, towers, forest, supply crates, spawn |
| `src/server/GiantFactory.lua` | part-built giant rig (rounded body, face, Motor6D waist/limbs/neck, glowing nape, kinematic mover) |
| `src/server/GiantService.lua` | giant AI, grabs, weak-spot damage, steam defeat, wave loop |
| `src/server/HunterService.lua` | leaderstats, twin swords, blades, resupply, server-side slash validation, cable relay |
| `src/client/GrappleController.lua` | flying hooks, taut-cable swing, reel, gas boost and dash, air spin slash, other hunters' cables |
| `src/client/Hud.lua` | crosshair, gas/blades, wave banner, toasts, "Caught!" screen |
| `src/client/GiantAnimator.lua` | client-only walk cycle (sway, bob), breathing, grab lunge, head that stares at you |

Movement runs on each player's own client, so the grapple feels instant.
Damage is always validated by the server (cooldown, blades left, real
distance to the nape).
