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

## 7. Lighting

Configured in `LightingSetup.lua`, applied once from `MapBuilder.Init()`.

- **`Enum.Technology.Future`** — required for the Bloom/ColorCorrection/
  Atmosphere combo below to render accurately; it's also what most current
  "neon on dark" trend games ship with.
- **`ClockTime = 20` (dusk), `Brightness = 1.6`** — moody without going
  pitch black. Neon trim needs *some* ambient darkness to read as glowing;
  full daylight would wash it out, but true night would hide the Parts'
  own base colors.
- **`BloomEffect` (Intensity 0.55, Threshold 1.35)** — tuned so `Neon`
  material actually blooms (that's the whole point of using Neon strips as
  trim) without blowing out `SmoothPlastic` surfaces, which sit below the
  bloom threshold.
- **`ColorCorrectionEffect` (+Saturation 0.15, +Contrast 0.1)** — a small
  global saturation/contrast lift so the palette's accent colors read as
  punchy without anyone having to hand-tune every Part's color.
- **`Atmosphere`** (Density 0.32, Haze 1.4) — soft depth falloff so the
  Arena (100 studs from the Hub) doesn't look like it's floating in a flat
  void when seen from a distance; it also sells the "world has scale" read
  without any skybox art.
- **`SunRaysEffect`** (Intensity 0.12, Spread 0.65) — a light, cheap
  sun-shaft glow through the Atmosphere haze at dusk. Kept low so it never
  competes with UI or CTF readability; this is polish, not a mood swing.
- **`Sky`** (`StarCount = 3000`, `SunAngularSize = 11`, `MoonAngularSize = 5`,
  `CelestialBodiesShown = true`) — a deliberate starfield at dusk instead of
  the engine's un-tuned default. No custom skybox/sun/moon texture ids are
  set: inventing an `rbxassetid://` here would either fail to load or show
  something unrelated, so every texture field is left at Roblox's own
  built-in default.
- **Path lamp posts** (`MapBuilder.buildPath`) — every connector path between
  zones now gets `WorldKit.Pillar` lamp posts every ~24 studs, alternating
  sides, capped in the same neon color as that path's own edge trim. Bare
  colored strips between zones were the visually weakest link in an
  otherwise-detailed map; this was the cheapest fix (a handful of extra Parts
  per path) for the biggest perceived gap.

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
