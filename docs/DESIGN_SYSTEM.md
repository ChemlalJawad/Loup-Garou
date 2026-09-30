# Design System — Brainrot Hatch Wars

This is the visual/UX reference for **Brainrot Hatch Wars**: why the palette
looks the way it does, how to build new UI that fits, how the world is
lit and laid out, and what a "v2" pass should reconsider. If you're adding a
new screen, a new zone, or a new Part-built prop, read this first.

The north star: **Adopt Me plaza polish + Pet Sim X / Steal a Brainrot
neon-on-dark saturation**, built entirely from `Instance.new` Parts and
UIKit components — no meshes, no image assets, no Wally packages. Every
decision below exists because it reads as "clean modern trend game" using
only that toolbox.

## 1. Palette

Source of truth: `src/ReplicatedStorage/Shared/Theme.lua`. This doc explains
the *why*; it never overrides the file's actual values (see §7 for proposed
changes, kept separate on purpose so nobody accidentally treats this doc as
authoritative over the code other agents already built against).

| Token | Value | Role |
|---|---|---|
| `Color.Background` | near-black navy `#12121A` | Base canvas — Workspace ground, screen backdrops. Never pure black; navy keeps it from feeling like a void, and gives Neon accents something to visibly glow against. |
| `Color.Surface` / `SurfaceRaised` | dark graphite `#1B1B28` / `#242434` | Panels, cards, platforms. `SurfaceRaised` is the hover/elevated variant — one step lighter, not a different hue, so elevation reads as depth rather than a color change. |
| `Color.Stroke` | `#34344A` | 1-2px outlines on cards/panels so surfaces separate from the background without needing a drop shadow everywhere. |
| `Color.AccentPrimary` (neon green) | `#39FF88` | The CTA color: coins, primary buttons, "you are here" markers, Hub trim. If a player should look at exactly one thing, it's this color. |
| `Color.AccentSecondary` (neon purple) | `#B14EFF` | Gems, Secret rarity, hatchery trim. Reserved for "premium/rare" moments so it doesn't compete with AccentPrimary for attention. |
| `Color.AccentDanger` / `Warning` / `Info` | red / amber / blue | Toast kinds and destructive actions only — never decorative. |
| `Color.Robux` | Roblox's own green `#35D664` | **Only** for Robux price tags and the Shop zone's accent, deliberately distinct from `AccentPrimary` so players never mistake a Robux price for a coin price at a glance. |
| `Rarity.*` | gray → blue → purple → gold → pink | Common → Secret. Reused verbatim in the Hatchery zone's egg pedestals so the physical world and the hatch-reveal UI teach the same color language. |
| `Team.Red` / `Team.Blue` | `#FF4757` / `#2E86FF` | CTF team identity. Used on floor washes, base banners, spawn pads in the Arena — never anywhere outside CTF, so red/blue stay unambiguous team signals. |

**Rule of thumb:** dark neutral surfaces do the heavy lifting; a saturated
accent color is a *sentence*, not a paragraph. If more than ~15% of a panel
is neon, it's probably overused — reserve full-saturation Neon material for
trim strips, glows, and CTAs, not fills.

## 2. Typography

| Token | Font | Use |
|---|---|---|
| `Font.Heading` | GothamBlack | Screen titles, the HUD wordmark, big numbers (hatch results, win banners). |
| `Font.SubHeading` | GothamBold | Buttons, nav labels, section headers inside panels. |
| `Font.Body` | GothamMedium | Toast text, descriptions, anything read at length. Never GothamBlack for body copy — it fights readability at small sizes. |
| `Font.Mono` | RobotoMono | Reserved for anything tabular/numeric that benefits from fixed-width alignment (e.g. a future stats screen). Not used yet — don't reach for it unless you're aligning columns of numbers. |

Chunky, bold, all-caps-leaning headings are the "brainrot"/trend-game
signature — lean into GothamBlack for anything meant to grab attention in
under a second (toasts, rarity reveals, the HUD title).

## 3. Spacing & corner radius scale

`Theme.Spacing` (4 / 8 / 12 / 20 / 32) and `Theme.CornerRadius` (Small 8px /
Medium 14px / Large 22px / Pill) are both small, deliberate scales — pick
from them, don't invent one-off values. As a rough guide:

- **Small (8px):** small chips/icons (the HUD logomark, badges).
- **Medium (14px):** buttons, toasts, cards — the default for "a clickable
  or readable rectangle."
- **Large (22px):** full panels/modals — anything that's a whole screen's
  container.
- **Pill:** currency pills, the nav bar, anything that should read as a
  single continuous capsule.

Generous negative space matters more than any single token: panels should
breathe (use `Spacing.L`/`XL` for outer padding, not `XS`/`S`), and the
Workspace zones follow the same instinct — wide plazas and clear walkways
rather than clutter (see §6).

## 4. Motion

`Theme.Motion` (Fast 0.12s / Normal 0.22s / Slow 0.35s, Quint Out) is the
one timing curve for the whole game. Concretely:

- **Fast (0.12s):** micro-feedback — button hover/press, a toggle flipping.
- **Normal (0.22s):** anything appearing/disappearing — toasts, panel
  open/close, the nav bar's selected-state change.
- **Slow (0.35s):** reserved for "a big deal just happened" — hatch
  reveals, flag captures, round-end banners.

Quint-Out (fast start, soft landing) reads as snappy without feeling
mechanical — keep using it rather than Linear/Back for consistency. Every
UIKit component (`Button`, `Toast`) already pulls these constants; new
components should too instead of hand-picking a duration.

## 5. UIKit components

`src/ReplicatedStorage/Shared/UIKit/` — read `init.lua` for the full list.
Every component follows the same shape: a `.new(props)` constructor,
`Util.Create` for raw instances, and only `Theme.lua` tokens, never
hardcoded colors. This pass added two:

- **`Toast.lua`** — a single auto-dismissing notification card (Surface
  background, kind-colored stroke + left accent bar, fade in/out over
  `Theme.Motion.Normal`, ~3.2s dwell). `Shell.Notify` is now a thin wrapper
  around `Toast.new` — there is exactly one toast implementation in the
  codebase now, not two competing ones. Reach for `UIKit.Toast.new(...)`
  directly if a future screen needs a one-off notification that isn't part
  of Shell's global queue.
- **`Divider.lua`** — a thin `Theme.Color.Stroke` rule (horizontal or
  vertical) for separating sections inside a `Panel` (e.g. a header from a
  scrolling list). Not wired into any screen yet — it's here for whoever
  builds the next panel that needs one, so they don't hand-roll a one-off
  `Frame`.

Both are registered in `UIKit/init.lua` alongside the existing components —
`local UIKit = require(ReplicatedStorage.Shared.UIKit)` then
`UIKit.Toast.new(...)` / `UIKit.Divider.new(...)`.

## 6. How the world is laid out

Everything below lives in `src/ServerScriptService/Server/World/`:
`MapBuilder.lua` (entry point), `WorldKit.lua` (a `UIKit.Util`-style
instance builder for Parts instead of GuiObjects), `LightingSetup.lua`, and
one module per zone (`HubZone`, `HatcheryZone`, `ShopZone`, `ArenaZone`).
Everything is `Anchored = true` Parts/cylinders — no unions except where
noted, no meshes.

```
                       Hatchery
                     (rarity eggs on
                      pedestals, purple
                      trim)             Shop kiosk
                          |            (Robux-green
                          |             trim)  \
                          |                     \
              Hub / Lobby Plaza  ----------------
              (neutral spawn,
               fountain centerpiece,
               green trim)
                          |
                          | long walkway (green trim,
                          |  entrance gate: red/blue pylons)
                          |
                    CTF Arena
              (Blue base - near end)
                    midfield cover
              (Red base - far end)
```

- **Spawn → Hub:** every player's *first* frame is standing on `HubSpawn`
  (the one `Neutral = true` SpawnLocation), facing the fountain. This is
  intentional: the calm, symmetric plaza is the "read the room" moment
  before anything else loads in.
- **Hub is the hinge.** Three short walkways (10-14 studs wide, neon-edged,
  colored to match whatever they lead to) radiate out to Hatchery, Shop,
  and the Arena. None of the Hatchery/Shop structures are functionally
  wired to anything — both screens open via the Shell nav bar regardless of
  where the player is standing — they exist purely so a player who's never
  opened a menu can still *see* "eggs happen over there" and "the shop is
  over there" and develop a mental map.
- **The Arena is deliberately far (a ~100-stud walkway) and visually
  distinct** — dark floor with a translucent red/blue tint per half, a
  glowing centerline, boundary walls, and an entrance gate (two pylons
  capped in each team's color) that telegraphs "this is the combat zone"
  before a player ever sees a HUD element for it. `RedBaseSpawn` /
  `BlueBaseSpawn` / `RedFlagStand` / `BlueFlagStand` are built with names
  read directly from `Constants.TEAMS` (never hardcoded strings) so this
  file can never drift out of sync with the CTF naming contract.
- **Ground plate + raised platforms.** A single large `BaseGround` Part
  sits under the whole map at a visible top of Y = -2. Every zone's own
  platform (and every connecting walkway) sits flush on top of it at Y = 0.
  Off the marked paths, the ground is 2 studs lower than the zones — a
  small, trivially-jumpable "sunken plaza" step rather than a hazard. This
  is a deliberate device (also used by other plaza-style trend games) to
  make the intended walkways read as *the* path without needing invisible
  walls.
- **Bands, not slabs.** The Hub plaza is three concentric bands (outer
  Slate/`Background`, mid `Surface`, inner round `SurfaceRaised`) rather
  than one flat square, each edged in neon — the cheapest way to make a
  flat plaza read as "designed" with zero extra assets. The Hatchery and
  Shop platforms use the same trick (a bordered platform, not a bare
  slab).
- **"More glow = rarer."** Hatchery eggs go from plain `SmoothPlastic`
  (Common/Rare/Epic) to `Neon` + a `PointLight` (Legendary/Secret), reusing
  the drop-tier language players already learn from the hatch-reveal UI.

If you're adding a new zone or prop: reuse `WorldKit.Part` /
`WorldKit.UprightCylinder` / `WorldKit.NeonBorder` / `WorldKit.Sign` /
`WorldKit.Spawn` rather than raw `Instance.new` calls — they bake in the
anchoring, smooth-surface, and rotation defaults every other zone already
relies on.

### New in the fun pass: Brainrot Parade and Fun Park

- **Brainrot Parade** (`ParadeZone.lua`, rect centred (-210, -200), south of
  the Hall of Fame): a red-carpet runway. Brainrots emerge from a glowing
  portal at the west end, walk east, and leave through an exit arch. The
  north half is an open shopping plaza with price and mutation info boards
  facing the arrival path. A secret chest hides behind the stage. Reached via
  Hall of Fame → Parade, and connected on to the Hatchery (through a doorway
  in the Hatchery's west wall, shared via `WorldLayout.Doors`).
- **Fun Park** (`FunParkZone.lua`, rect centred (210, 300), north of the
  Market): candy-colored playground. Chain-bounce trampolines, jump pads onto
  a floating island (chest), a spiral obby tower (chest at the summit), and
  an ice slide from the summit back down to the entrance. Reached via
  Market → Fun Park.

### Landscaping and ambient life

- **Ground** is grass now (`MapBuilder` BaseGround, RGB 96,170,88) so the
  space between zones reads as a park, not a void.
- **`LandscapeZone.lua`** (Order 200, after every real zone) scatters ~190
  props with a fixed seed, so every server has the same park. It stays 7
  studs clear of every zone rect and 4 studs clear of every path
  (`PathRegistry`, filled by `MapBuilder` before zones build), with 9 studs
  between props. Mix: round/pine/candy trees, bushes, flower beds, rocks,
  balloon clusters, giant mushrooms.
- **Hidden chests** in the wilds: NorthWest (-265, 410), SouthEast
  (270, -300), West mushroom grove (-250, 250). 15 min cooldown each.
- **Hub corner gardens**: a candy tree, two flower beds and balloons in each
  of the four bare outer-ring corners.
- **Ambient Brainrots** (`AmbientLifeController`): 10 client-side wanderers
  on the lawns within 170 studs of the Hub, never inside a zone. Tap to pet.

### Base biome

`BiomeZone.lua` (Order 150, before LandscapeZone) turns the plate into a
valley: rolling edge hills with an invisible boundary wall, a darker grass
skirt and hazy horizon hills, a lily pond at (-220, 330), meadow patches, and
firefly/pollen emitters tagged with a `DecorTime` attribute ("Night"/"Day")
that LightingController honours. Keep-out rects for the pond and hill band go
into `PathRegistry`. `SkyController` adds client-side clouds and the Lucky
Rainbow arc north of the Arena.

**Map design pass:** paths switched from the UI's dark panel colour to warm
cream cobblestone (the neon trim still colour-codes each route), and every
lamp post has a flower bed at its foot. A dirt trail branches west off the
Arena main street to the Lily Pond (signed "<- LILY POND"), which also has a
picnic blanket on its west shore. Two giant statues (Gold Tralalero Astrale
in the west wilds, Diamond Crocobrivido Vulcanico between the Market and Fun
Park) are skyline landmarks, positioned via `WorldLayout.Landmarks`.

### Themed wilds (`WildsZone.lua`, Order 160)

Rects live in `WorldLayout.Wilds`; plan in `docs/map-plan.png`.

- **Candy Land** (around the Fun Park path, 210,152): pink "sugar" terrain
  (Salt), lollipops, candy canes, glassy gumdrops you can hop on, and
  cotton-candy trees.
- **Crystal Grove** (north of the pond): violet Slate ground, glass crystal
  clusters with neon cores. One cluster in three carries a night light;
  sparkles drift over the grove.
- **Tulip Fields** (south strip): colour-striped beds on dirt ridges and a
  windmill. The sails are spun client-side via the `Spinner` tag.
- **Rock outcrops**: 22 terrain boulders in open grass.
- **Backdrops** (`WorldLayout.Backdrops`): a smoking volcano beyond the south
  edge (lava crater, glowing streams, embers) and snow-capped mountains
  behind the Arena. They're outside the boundary wall: scenery only.

## 7. Lighting

Lighting is split in two:

- **`LightingSetup.lua` (server, once at boot)** creates the post effects
  (Bloom, ColorCorrection, Atmosphere, SunRays, Sky) and a bright-afternoon
  fallback look.
- **`LightingController.lua` (client, continuous)** runs the day/night cycle,
  per-zone color grading and decorative-light management, all driven by the
  shared `LightingConfig.lua`.

### Day/night cycle

- The time of day is a pure function of `workspace:GetServerTimeNow()`
  (`LightingConfig.StateAt`). Every client computes it locally, so **nothing
  replicates `Lighting` over the network**, yet everyone sees the same sky.
  The server uses the same function to ask "is it night?" (the Parade
  boosts mutation odds at night).
- **15-minute cycle, 70% daytime.** A young audience expects a bright,
  readable world by default; night is the special moment where neon trim and
  glowing Brainrots take over. A short cycle means a normal session always
  sees at least one sunset.
- Day ↔ night lerps `Brightness`, `Ambient`, `OutdoorAmbient`,
  `ColorShift_Top` and `ExposureCompensation`, with a warm golden-hour tint
  around sunrise/sunset. Night keeps a small exposure lift so players on
  phones in bright rooms can still see where they're going.
- **Bloom** follows the sun: high threshold by day (only `Neon` glows, sunlit
  white plastic doesn't bleed), lower threshold and stronger intensity at
  night.
- **Sun rays** peak at golden hour, when a low sun through haze actually
  looks like something, and switch off at night.
- Players get a toast at dusk and dawn; at night it tells them the Parade
  has better mutation odds, so the cycle has a gameplay reason to matter.

### Zone moods

Each zone in `WorldLayout` has a subtle color grade (`LightingConfig.ZoneMoods`:
tint, saturation, contrast, atmosphere color/density). Crossing into a zone
blends to its mood over ~1.6s, so each area *feels* like a distinct place
without a loading screen. The Arena deliberately gets **less** haze and
**more** contrast: readability of opponents beats mood in a PvP space. The
Fun Park gets the most saturation so it reads as "the fun place" from across
the map. Moods are subtle on purpose — a Legendary's rarity color must read
the same everywhere.

### Performance (mobile first)

Most young players are on phones and tablets, so:

- The controller writes to `Lighting` 4× per second, not every frame (every
  frame only during a ~1.6s zone blend).
- `WorldKit.Light` / `WorldKit.Emitter` tag decorative lights and particles
  (`DecorLight`, `DecorEmitter`). Lamps fade in at dusk and are **disabled in
  full daylight** — fewer active lights by day is a free win. On low graphics
  quality (manual quality 1–3, or "Automatic" on a touch-only device) all
  decorative lights and particles are switched off. Gameplay lights (CTF flag
  stands) opt out with `Gameplay = true` and stay on.
- `Lighting.Technology = Future` is set in `default.project.json` (Rojo
  writes it into the place); the script assignment is only a `pcall`
  fallback, because `Technology` isn't reliably writable from game scripts
  and an unguarded failure there used to risk skipping the whole setup.

### Fixed pieces

- **`Sky`** — deliberate star count and sun/moon size; no custom texture ids
  (inventing an `rbxassetid://` would fail to load or show something
  unrelated), so textures stay at Roblox's defaults.
- **Path lamp posts** (`MapBuilder.buildPath`) — lamp posts every ~24 studs
  along every connector path, now with a real `PointLight` so paths are lit
  at night. Paths leading to zones not visible from the Hub also get a
  floating signpost.

### CoreGui recommendation (not implemented here)

Roblox's default Backpack hotbar can visually collide with the custom nav
bar's screen position (both anchor near the bottom of the screen). This
doc **recommends** whoever owns `CTFController`/ability input confirm
whether abilities are Tool-based (need Backpack) or purely
keybind/UI-based (safe to hide) before calling
`StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)`. That
toggle was deliberately **not** added from `MapBuilder`/`LightingSetup` in
this pass — it's a client-affecting global switch with no way to test-run
it here, and getting it wrong (hiding a hotbar players actually need) is
worse than leaving Roblox's default chrome alone. Leave Chat/PlayerList
untouched regardless — both are expected, low-risk defaults for a social
hub game.

## 8. Shell.lua polish pass (this round's changes)

`Shell.lua`'s public API (`Init`, `GetScreenGui`, `RegisterNavButton`,
`SetCurrency`, `Notify`) is unchanged — every other agent's controller
calls these exact same names/parameters. What changed is internal:

- **Top bar** now has a translucent gradient backdrop (`Background` +
  `UIGradient`, approximating "glassy" since a true blur isn't available
  without a full-viewport post-effect) and a thin glowing bottom seam
  separating the HUD from the world.
- **Logomark + wordmark.** A small rotated-square accent mark plus a
  green-to-white gradient on the title text, instead of a single flat
  `TextLabel`, so the top-left reads as a brand lockup.
- **Nav bar** gets a faked drop shadow (`addDropShadow` — a slightly
  larger, darker, semi-transparent duplicate Frame behind it; there's no
  shadow image asset to use for a real one) and a best-effort "selected"
  highlight: clicking a nav button tints its text/stroke `AccentPrimary`
  until another one is clicked. This is cosmetic only — Shell has no way to
  know if a screen was later closed by some other means — so it never
  gates or changes what a caller's `OnClick` actually does.
- **Toasts** now render via `UIKit.Toast.new` (see §5) instead of an inline
  builder, with one small visual addition (a kind-colored left accent bar)
  layered on top of the original look.

## 9. v2 suggestions (do not implement without a broader pass)

Things worth reconsidering for `Theme.lua` once there's room to touch
values other agents have already built UI against:

- `Color.AccentPrimary` (neon green, `#39FF88`) and `Color.Robux`
  (`#35D664`) are close enough in hue/lightness that side-by-side (e.g. a
  coin price next to a Robux price in the Shop) they can read as "the same
  green" at a glance. Consider pushing `Robux` more teal or `AccentPrimary`
  more lime to widen the gap.
- No `Color.Overlay`/scrim token exists for modal backdrops — every future
  full-screen panel (Egg reveal, Shop confirm) will likely want a
  consistent "dim the world behind me" color; right now each screen would
  have to invent its own.
- `Theme.CornerRadius` has no "None"/0 option for things that should be
  hard-edged (e.g. the Arena's floor tint washes, which are Workspace Parts
  and don't use `UICorner` anyway, but a future full-bleed UI banner might
  want a deliberately square edge). Not urgent, just missing.
- Consider a `Theme.Elevation` shadow-color/opacity pair now that
  `Shell.lua` hand-rolls a drop shadow locally (`addDropShadow`) — if a
  second screen wants the same treatment, it'll currently have to
  reimplement it rather than pull a token.
