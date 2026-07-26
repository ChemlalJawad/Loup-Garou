# Brainrot Roster — Canonical Reference

This is the **single source of truth** for every Brainrot character in the
game. The Egg system, the CTF ability system, and marketing copy all read
from this list so a "Rondine Ravioli" means the same thing everywhere.

All characters are **original designs** in the Italian-absurdist "brainrot"
meme style (animal + food/object mashup, over-the-top Italian name) — inspired
by the internet trend, not copies of existing viral characters. That keeps
the game safe to brand and monetize without leaning on someone else's IP.

Until real meshes/animations are modeled, build each Brainrot in Studio as a
simple stylized part-built or block-rig character using the `BodyColor` /
`AccentColor` below, tagged with a `BrainrotId` StringValue matching the `Id`
column, `ClassName` used by both `EggConfig` and `CTFConfig`.

| Id | Display Name | Rarity | Visual Concept | CTF Ability (concept) |
|---|---|---|---|---|
| `Spaghettoro` | Spaghettoro | Common | Wild boar with spaghetti tusks & marinara mohawk | **Meatball Dash** — short forward speed burst |
| `CannoliniVolpe` | Cannolini Volpe | Common | Fox wrapped in a crispy cannoli shell | **Sugar Rush** — +15% move speed, 5s |
| `PolpoMotorino` | Polpo Motorino | Common | Octopus riding a tiny moped on its tentacles | **Turbo Squirt** — speed burst that leaves a slick slowing chasers |
| `PinguinoMandolino` | Pinguino Mandolino | Common | Penguin playing a mandolin, trailing music notes | **Sonata Slow** — musical pulse slows nearby enemies briefly |
| `BroccolinoTurbanti` | Broccolino Turbanti | Common | Broccoli floret in a chef's turban | **Steam Cloud** — vision-blocking steam puff to cover a retreat |
| `LucertolaFocaccina` | Lucertola Focaccina | Common | Lizard with a focaccia-bread back shell | **Bread Shield** — ~1s tag immunity |
| `GirafferroEspressone` | Girafferro Espressone | Rare | Giraffe with an espresso-machine head, steaming horns | **Espresso Shot** — instant speed burst, resets dash cooldown |
| `RondineRavioli` | Rondine Ravioli | Rare | Swallow with ravioli-pocket wings | **Ravioli Toss** — ranged projectile that stuns on hit |
| `ScoiattoloCannoncino` | Scoiattolo Cannoncino | Rare | Squirrel strapped to a mini cannon backpack | **Nut Barrage** — cannon-jump forward mobility burst |
| `TartarugaVespaccia` | Tartaruga Vespaccia | Rare | Turtle with a Vespa-scooter shell | **Shell Sprint** — big speed boost, sharp turns disabled |
| `FenicotteroPizzaiolo` | Fenicottero Pizzaiolo | Epic | Flamingo spinning pizza dough on one leg | **Dough Toss** — spinning pizza disc tags & stuns at range |
| `PipistrelloMarinaro` | Pipistrello Marinaro | Epic | Bat in a sailor cap, sail-shaped wings | **Night Glide** — brief flight, crosses gaps, ignores fall damage |
| `CannoloTrombonini` | Cannolo Trombonini | Epic | Walking cannoli playing a trombone | **Brass Boom** — knockback shockwave, clears a path |
| `CrocobrividoVulcanico` | Crocobrivido Vulcanico | Legendary | Volcanic crocodile, lava cracks & bomber jacket | **Magma Slam** — AoE stun slam, strong flag-stand defense |
| `SqualezzaFerroviaria` | Squalezza Ferroviaria | Legendary | Shark fused with a locomotive front, steam plume | **Rail Charge** — unstoppable charge, knocks enemies aside |
| `TralaleroAstrale` | Tralalero Astrale | Secret | Cosmic three-legged shark-sneaker hybrid wreathed in starlight | **Starlight Warp** — short teleport dash, longest-range escape/flank in the game |

## Rarity drop weights (relative, per egg — tune in `EggConfig.lua`)

| Rarity | Basic Egg | Golden Egg | Secret Egg |
|---|---|---|---|
| Common | 82% | 45% | 10% |
| Rare | 15% | 35% | 30% |
| Epic | 3% | 17% | 35% |
| Legendary | — | 2.8% | 20% |
| Secret | — | 0.2% | 5% |

`EggConfig.lua` is the executable version of this table — if the two ever
disagree, `EggConfig.lua` wins and this doc should be updated to match.

## Ability power budget

Common abilities: mobility/utility only, ~4-6s cooldown, no direct
crowd-control on enemies (except a short self-buff). Rare abilities may
briefly slow or stun. Epic abilities hit at range or clear a small area.
Legendary abilities are strong single-target/AoE tools built for
attacking/defending the flag stand. Secret (`TralaleroAstrale`) is the one
exception to "no raw power creep": it's a pure-mobility teleport so it stays
skill-expressive rather than just strictly-better-than-Legendary.
