# Giant Hunters

A grapple-rig action game for Roblox: defend a walled district against
giants. Swing between the rooftops on two cable hooks and take giants down
by slashing the glowing weak spot on the back of their neck. It's inspired
by the "titan-slaying" genre, with an original setting and names, and it's
child-friendly: no gore, grabs are a game of wriggle-free, and defeated
giants puff away into steam.

This is a separate Rojo project from Brainrot Hatch Wars, in the same repo.

![The district](world-preview.jpg)

![Giants and a hunter with twin swords](giants-preview.jpg)

![Day and night](day-night-preview.jpg)

![The Great Forest and the old castle](zones-preview.jpg)

![Giant looks, and the hunters' uniform and gear](hunters-preview.jpg)

*Offline previews, rendered outside Roblox from the same building code
(so the lighting isn't Roblox's). Not Studio screenshots.*

## Run it

```bash
cd GiantHunters
rojo serve
```

In Studio, open a new **Baseplate** and delete the `Baseplate` and
`SpawnLocation` parts. Then **Plugins → Rojo → Connect** and press **Play**.
The district, the giants and the HUD all build themselves. You can also
`rojo build -o GiantHunters.rbxlx` and open the file.

## The world

- **The Great Wall**: a ring of stone 110 studs high round the whole town,
  with a walkway, merlons, stone bands, watchtowers, and iron grates where
  the river runs under it. You start **on top of the north wall**, with the
  whole town below you.
- **The south gate** is where every round starts: the **Wallbreaker**, a
  giant taller than the wall, appears outside in a flash of steam, peers
  over the gate and kicks it in. The doors burst inward, and the giants
  come through the breach. Save the district and the gate is rebuilt.
- **The town**: ring roads, avenues from a central plaza, and tight rows
  of tall old houses (stone ground floors, timber-framed upper floors,
  steep tiled roofs, chimneys with smoke, washing lines across the alleys).
  Every face is something to hook.
- **Landmarks**: the plaza fountain and its statue of the first hunter, the
  church bell tower (the highest perch in town), the hunters' headquarters
  and supply depot, the market, a garden, the gate square with barricades,
  bridges over the river.
- **Outside** (the land reaches 1300 studs from the centre): the forest of
  giant trees (a hunters' platform with a supply crate up one trunk),
  farms with a windmill and wheat fields, the road from the gate, the
  plains, hills all round.
- **The Great Forest** (east): 76 trees taller than the wall (160-230
  studs) and nothing else, spread over half a kilometre. The place to
  swing from trunk to trunk at full speed; a few trunks carry platforms
  with supplies and torches.
- **The Training Grounds** (north, behind the wall): practice trees and 18
  wooden giant dummies, some up on stilts, with a target on the back of
  the neck. Cut them to practise your approach: the HUD tells you your
  speed and whether it was a clean cut. No blades used, no points.
- **The old castle** (west), on its hill: curtain walls with one side
  fallen in, corner towers, a tall round keep, a supply crate.
- **Signal towers** every 130 studs along the dirt roads that link the
  gate, the castle, the forest and the training grounds (and down the
  south road), and **groves of giant trees** dotted over the open plains:
  there's always something to hook onto, so you can cross the whole land
  on your cables.
- **Wall cannons** either side of the gate: fire one at a giant to daze it.

## The hunters' uniform

Every hunter wears the corps' uniform, whatever their avatar. The server
re-dresses the avatar through its HumanoidDescription (no asset ids):
classic shirt and pants, layered clothing and back, waist, shoulder, front
and neck accessories come off (hair, hats and the face stay), the body goes
back to the default shape at normal scale, and the body colours become the
uniform: a white shirt, brown jacket sleeves, white trousers. On top go the
thin pieces: the jacket's panels over the torso and its collar, darker
cuffs, tall dark boots, leather straps across the chest and round the
thighs, a belt, and a green cape with the corps' crossed-blades emblem. If
the avatar can't be re-dressed, fabric shells cover every body part
instead. The grapple rig is on show: the reel box at the small of the back
with its hook launchers (the cables leave from their tips), a gas tank
either side, and a blade box low on each hip, behind the hands. The swords
sit in the fist (the hand's grip attachment, on R15, R6 and Rthro alike),
tipped up a little, with a pistol-grip handle and a trigger, a squared hilt
and a long blade scored with snap lines and cut off at an angle at the tip.

## Day and night

A full 24 hours passes every 16 real minutes (`Config.DayNight`). The
server only moves the clock; each client paints the sky from it
(`Sky.lua`): blue noon, a gold and red sunset, a dark blue night with stars
and a big moon, an orange dawn, with the atmosphere, colours, bloom, sun
rays and clouds all changing with the hour.

At night it's properly dark: torches burn along the whole wall and round
the plaza and the gate square, the street lamps light up along the
avenues, ring roads and bridges, and 4 windows in 10 glow warm. The
giants' tiny pupils glow orange in the dark, and they walk 20% faster.

## Titan shifters

Now and then a glowing **purple crystal** appears in town (the plaza, the
headquarters, the market, the gate square or the garden). Whoever takes it
gets the **titan power** (never more than 2 players at once) and picks a
side:

- **Hunters' side** (blue outline): your punches crush giants (they count
  as your takedowns) and your roar dazes them.
- **Giants' side** (red outline): your punches knock hunters out (they
  respawn on the wall) and your roar blows them away. Hunters can cut your
  nape: 3 hits and you're thrown out of the titan, and the power is gone.

Titans on opposite sides can fight each other. Press **T** to transform
(60 s, then a 40 s cooldown) and T again to change back. As a titan, click
or F punches and G roars. Hooks, gas and blades are put away.

## The Beast Giant

From wave 3 a **Beast Giant** sometimes appears (one at a time). It throws
**boulders** at hunters who think they're safe on the rooftops or far
away (they take over a second to land: keep moving), and **roars** away
anyone who comes close. Worth 12 points.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Left / right hook (hold, then swing) | Q / E | L1 / R1 | "L Hook" / "R Hook" |
| Reel in (hooked) / gas boost (in the air) | hold Space | A | "Gas" |
| Gas dash | Shift | B | "Dash" |
| Slash with both blades (a full spin in the air) | Click or F | X | "Slash" |
| Signal flare | G | Y | "Flare" |
| Transform into a titan (with the titan power) | T | D-pad up | "Titan" |
| Titan: punch / roar | Click or F / G | X / Y | "Punch" / "Roar" |
| Wriggle free when grabbed | mash any of the above | | tap |
| Resupply gas & blades | stand at a crate with a blue beam | | |
| Fire a wall cannon | stand next to it | | |

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
- Gas shows as white jets behind you, the view widens and the wind picks
  up with speed. Other hunters see your cables.

## How it plays

- **Rounds**: a short breather, the Wallbreaker breaches the gate, then 5
  waves pour in. The last wave brings an **Armored Giant**. Clear it and
  the district is saved; the next round is a little harder.
- **The three cuts**:
  - **Nape** (the glowing lump on the back of the neck), from behind or
    the side: the only thing that takes a giant down. Hit it going fast
    (35+ studs/s) for a **clean cut** (full damage); slow hits do half.
  - **Eyes** (from in front): the giant is **dazed** for 4 s: hands over
    its face, stars round its head, no grabbing.
  - **Ankles**: the giant drops to its **knees** for 4.5 s, bringing its
    nape within easy reach.
- **Giants**:
  - **Small / Giant / Colossal**: they chase the nearest hunter they can
    reach. On a rooftop above their heads, you're safe.
  - **Runner** (an abnormal): fast, zig-zags, leaps, and picks its own
    target. Yellow shorts, odd eyes.
  - **Sprinter** (an abnormal, from wave 3): lean and quick, zig-zags and
    leaps like a Runner, ponytail and a smirk. She can cover her nape with a
    crystal hand.
  - **Crawler** (now and then from wave 1): slow, on all fours, its nape
    right on top. The easy one for new hunters.
  - **Armored Giant**: rock plates in pieces with dark seams and a helmet
    set back off the eyes; the plate over its nape has to be cracked (3
    hits, and you see the cracks glow and spread) before the nape can be
    cut.
  - **Beast Giant**: ape-like, dark fur all over with shaggy tufts, a bare
    face, big ears, glowing eyes, knuckles near the ground. It steams.
  - **Wallbreaker**: rock skin cracked with glowing orange seams, glowing
    eyes, a heavy brow and a big jaw, steaming. Event only.
  - All of them are part-built, soft and rounded, with a hunched walk.
    Their pupils follow the nearest hunter and they blink. Each rolls a
    body (lanky, stocky, chubby, big-headed, or **gangly**: thin as a rake,
    stooped, arms hanging past its knees), an expression (a wide toothy
    grin, a dopey half-asleep stare, a gaping mouth, a lopsided smirk, a
    round "oh", buck teeth), brows (worried, angry, raised, flat), a nose
    (round, button, long, wide), hair (bald, cap, mop, spiky, bowl,
    mohawk, bun, curly; dark, brown, blond, ginger, grey or white),
    sometimes a beard, and ribs on the skinny ones. Hair never covers the
    nape. Giants 46 studs and up steam a little.
- **Grabs**: a giant raises its arms first (the warning). If it catches
  you, you're held in its hand: **mash to wriggle free**, or a friend can
  cut you loose (any cut on that giant). Not free after 3.5 s? You're
  caught and sent back to the wall.
- **Swats**: fly round a giant's head in front of it and it swats you
  away. It can't see behind it - **attack from behind**.
- **Blades**: a sword in each hand, 8 blades per life, one used per hit.
  With none left they turn dull and grey. Resupply at a crate (the wall
  post, the plaza, the headquarters, the market, the gate square, the
  forest platform).
- **Gas**: used to reel in, boost and dash. Refills slowly on the ground,
  or fully at a crate.
- **Score**: points per giant (Small 1, Giant 2, Runner 3, Colossal 4,
  Armored 8), times your **combo** (takedowns within 8 s of each other, up
  to x5), +1 for a takedown at 70+ studs/s. Trips, dazes and cannon hits
  are worth 1, cracking armour 2, rescuing a friend 3. Ranks: Recruit,
  Scout, Hunter, Veteran, Captain, Commander.

## The HUD

Crosshair with left/right hook marks (yellow flying, green hooked); the
gear panel (two gas tanks, two boxes of four blades, your speed, rank and
points); a hint when a cut is in reach ("SLASH THE NAPE!", "TRIP",
"DAZE"); the round and wave banner; announcements; a kill feed; the combo
counter; a radar that turns with the camera (giants red, runners orange,
armoured grey, hunters blue, crates cyan, the gate yellow, the wall a
ring); the GRABBED! screen with a wriggle meter.

## Sounds

The game uses a few sound files that ship with every Roblox client
(`rbxasset://sounds/...`: the classic sword slash, lunge and unsheath, the
character landing thud, falling wind, water splash). Nothing is uploaded
and there are no asset ids to set up. They haven't been checked in Studio
from here, so if one doesn't play, swap its id in `Config.Sounds` for any
sound you've uploaded (`rbxassetid://...`).

## Code map

| File | What |
|---|---|
| `src/shared/Config.lua` | every tuning number: grapple, blades, cuts, scoring, giants, waves, world, sounds |
| `src/shared/Geo.lua` | the district's geometry and the giants' route-finding (round the wall, through the gate only when breached) |
| `src/server/MapBuilder.lua` | builds the world from the four layers below |
| `src/server/World/Ground.lua` | Smooth Terrain: paving and roads, grass patchwork, fields, river, hills |
| `src/server/World/Wall.lua` | the Great Wall, the breachable gate, watchtowers, cannons, the spawn post |
| `src/server/World/Town.lua` | row houses, plaza, church, headquarters, market, garden, bridges |
| `src/server/World/Wilds.lua` | giant forest, the Great Forest, training grounds, castle, signal towers, groves, farms, windmill, roads, plains, giant entry points |
| `src/server/World/Kit.lua`, `Layout.lua` | shared part helpers and set pieces; where the big pieces go |
| `src/server/GiantFactory.lua` | part-built giant rig (rounded body, face, armour, Motor6D waist/limbs/neck, glowing nape, kinematic mover) |
| `src/server/GiantService.lua` | giant AI, grabs and holds, swats, the three cuts, armour, takedowns, the Wallbreaker |
| `src/server/WaveService.lua` | rounds and waves (and the odd Beast Giant) |
| `src/server/DayNightService.lua` | the 24-hour clock |
| `src/server/ShifterService.lua` | the titan crystal, sides, transforming, punches, roars, titan napes |
| `src/server/HunterService.lua` | characters, leaderboard and ranks, twin swords, blades, resupply, slash validation, combos, flares, cable relay |
| `src/server/HunterGear.lua` | the hunters' uniform, cape and grapple rig, built over each avatar |
| `src/server/CannonService.lua` | the wall cannons |
| `src/server/Broadcast.lua` | kill feed, announcements, camera shakes |
| `src/client/GrappleController.lua` | flying hooks, taut-cable swing, reel, gas boost and dash, air spin slash, flares, being grabbed or swatted, other hunters' cables |
| `src/client/GiantAnimator.lua` | client-only animation (walk, grab, hold, swat, kneel, daze, leap, kick, stare), footsteps, daze stars |
| `src/client/Hud.lua`, `Radar.lua` | the HUD and the radar |
| `src/client/Effects.lua` | camera shake, sounds, hit bursts, the windmill |
| `src/client/SkyController.lua`, `src/shared/Sky.lua` | the sky by the hour; lamps, torches, windows and giants' eyes at night |
| `src/client/ShifterController.lua` | choosing a side, T to transform, titan punch and roar |

Movement runs on each player's own client, so the grapple feels instant.
Damage is always validated by the server (cooldown, blades left, real
distance to the nape, eyes or ankle).
