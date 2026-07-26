# Marketing & Growth Strategy — Brainrot Hatch Wars

This doc is the marketing counterpart to `ARCHITECTURE.md` and
`BRAINROT_ROSTER.md`. It covers positioning, store page copy, creative
briefs, monetization framing, and a 90-day launch plan. It does not touch
code or in-game config — anything here that implies a new system (see the
referral hook in Section 5) is a **request to the build team**, not
something this doc changes itself.

Everything below assumes the confirmed core loop: hatch an Egg (Basic /
Golden / Secret, paid in Coins or Gems) → roll a Brainrot across 5 rarities
(Common → Rare → Epic → Legendary → Secret) → equip one → its unique ability
fires in Capture the Flag (Team Ember vs. Team Frost) → win rounds, earn
Coins, hatch more. All 16 Brainrots are original designs in the meme's
Italian-absurdist style — never market them as *the* famous viral
characters. That's both a legal safety rail and a copy angle: "our own
unhinged cast," not a knockoff.

---

## 1. Positioning & Title Options

Roblox discovery is still mostly keyword-matched search + thumbnail CTR, so
the title has two jobs: contain "Brainrot" (the trend everyone is typing
right now) and signal *both* hooks — this isn't just a gacha sim, it's a
gacha sim that feeds a PvP mode. A title that only signals one hook
undersells the game and, worse, sets the wrong expectation and tanks
retention/ratings from players who came for the wrong genre.

| # | Title | Rationale |
|---|---|---|
| 1 | **Brainrot Hatch Wars** *(current)* | "Brainrot" leads (matches raw search volume), "Hatch" flags the collector/gacha loop, "Wars" flags PvP — all three load-bearing words, three words total, reads instantly at thumbnail size. No wasted characters. |
| 2 | Brainrot Battle Hatch | Same three ideas, "Battle" moved forward. Marginally better if Roblox's search weights earlier tokens more heavily on "battle"-style queries, but "Hatch Wars" scans more naturally as a phrase — most playtesters read it faster. |
| 3 | Hatch a Brainrot: Capture Wars | Mimics the "[Verb] a [Noun]" pattern ("Steal a Brainrot", "Grow a Garden") that's currently over-indexed in Roblox's autocomplete/related-search surface, so it can catch spillover traffic from that exact search pattern. Downside: longer, the colon subtitle gets truncated in the app's thumbnail title bar on mobile, and "Capture Wars" alone doesn't obviously mean CTF. |
| 4 | Brainrot Clash: Hatch & Capture | Most literal description of the loop, good for App Store–style clarity, but "Clash" is an overused genre word (tower-defense/strategy connotation) that could mismatch player expectations at a glance. |
| 5 | Brainrot Tag Wars | "Tag" is more universally understood than "CTF" by the actual Roblox age bracket (skews younger than "capture the flag" terminology assumes), but it undersells the collection half entirely — reads as a tag game with a brainrot skin, not a hatching game. |

**Recommendation: keep `Brainrot Hatch Wars`.** It already does the job —
don't spend design/eng cycles on a rename. It's short enough to never
truncate, contains the #1 search keyword, and "Hatch"/"Wars" are the two
words that correctly set expectations for both halves of the loop. Revisit
only if post-launch search-term reports show people are typing "steal a" or
"grow a" phrasing at meaningfully high volume against this game's impression
data — that's the one signal worth an A/B retitle test for.

---

## 2. Store Page Copy

### Tagline (under 60 characters — shows under the title in search)

> **Hatch Brainrots, equip a power, capture the flag.** *(49 chars)*

Backup option if that reads too listy for the slot: **"Hatch a Brainrot.
Battle for the flag. Repeat."** (46 chars) — leans harder on the loop's
addictiveness ("Repeat.") over its mechanics.

### Full Description (~220 words)

```
🥪 THE BRAINROT TREND, NOW WITH TEAMS. 🥪

Crack open an Egg. Meet your new Brainrot. Take it to war.

🥚 HATCH — Basic, Golden, and Secret Eggs, paid in Coins or Gems.
Every hatch is a reveal moment. Every reveal could be the one.

🐊 COLLECT — 16 wildly unhinged, 100% original Brainrots across
5 rarities, from Common street food-animal mashups all the way up
to the ultra-rare Secret tier. Yes, you WILL scream when you get one.

⚡ EQUIP — Every Brainrot brings its own Capture-the-Flag ability
to the field. Speed bursts. Stuns. Teleports. AoE slams. Pick your
fighter, pick your playstyle.

🚩 BATTLE — Team Ember vs. Team Frost, 5v5 Capture the Flag.
Grab the flag, guard your base, win the round, cash in Coins —
then go hatch more.

This is OUR brainrot cast. Original characters, original chaos,
built for a game mode that actually has stakes.

🔁 The loop: Hatch → Collect → Equip → Battle → Repeat.

⭐ Daily login rewards
⭐ New Brainrot drops every week
⭐ VIP perks, Double Coins, Double Luck — go faster if you want to,
   grind for free if you'd rather

👉 Hatch your first Brainrot right now. Then go win with it.
```

Style notes for whoever pastes this in: short lines beat paragraphs, emoji
as bullet anchors (not decoration spam — one per line, consistent icon per
section), and the CTA is a verb ("Hatch your first Brainrot right now"), not
a vague "play now."

---

## 3. Icon & Thumbnail Creative Brief

No image pipeline here, so this is written as an actual brief to hand a
designer — composition, subject, color, and the psychological hook each
asset is selling.

### Icon (512×512)

**Subject:** A single close-up head/bust shot of **Tralalero Astrale**
(Secret rarity — cosmic three-legged shark-sneaker hybrid, wreathed in
starlight). Not a Common. The icon's job is to be the thing players are
chasing, not the thing they already have — classic collector-game icon
logic (see: any gacha app icon, it's never the starter unit).

**Color story:** Deep magenta-to-violet gradient background, high
saturation, with the starlight wreath rendered as a few bright cyan/white
sparkle points — that cyan-on-violet contrast is what survives being
shrunk to a 32px app-tray icon. Avoid busy background detail entirely;
Roblox icons compete at thumbnail sizes where anything under ~15% of the
canvas disappears.

**Composition:** Centered, tight crop (character fills ~80% of frame),
thick clean outline (3-4px equivalent at full res) so the silhouette still
reads with zero color information — this is the single most important
test: screenshot it, convert to grayscale, shrink to 64px, and check it's
still identifiable as a face, not a blob.

**No text, no logo, no UI chrome.** Icons with text almost always lose
legibility below 100px and Roblox's own icon guidelines discourage it.

### Thumbnails (1920×1080, 3 concepts)

**1. "Which one will you get" — rarity flex shot**
A cracked-open Egg mid-explosion at center frame, light burst radiating
out, with 5-6 Brainrots arranged in a loose arc around it — one per
rarity tier, each haloed in its rarity color (grey → blue → purple →
gold → prismatic/rainbow for Secret). The viewer's eye should snap
straight to the rainbow-glowing one in the back. **No text**, or at most
a tiny "NEW" flare — let the rarity-color staircase do the selling.
**Emotion:** the gacha curiosity gap — "which one am I going to pull."

**2. "Action moment" — mid-capture chase**
Low-angle, dynamic composition: a flag carrier (red, Team Ember) mid-sprint
toward camera, motion-blurred, with a blue Team Frost Brainrot mid-ability
in pursuit — good pick is **Squalezza Ferroviaria** (Legendary, Rail
Charge) leaving a steam-trail knockback effect, since "unstoppable train
shark chasing you" is inherently a strong silhouette. Red vs. blue color
blocking should be unmistakable even desaturated. No text needed; if
required, a single short stamp like "CAPTURE THE FLAG" bottom-left, small.
**Emotion:** stakes/tension — this is a real competitive game, not just a
hatching sim.

**3. "Before/after power fantasy" split shot**
Left third: a plain, un-equipped default avatar, desaturated/grey,
small in frame. Right two-thirds: the same avatar mid-ability-activation
with an equipped high-rarity Brainrot (good pick: **Crocobrivido
Vulcanico**, Legendary, mid Magma Slam — lava cracks, AoE shockwave ring
on the ground, strong glow). A single graphic arrow or "→" is the only
text element, or none at all. **Emotion:** aspirational progression —
"this is what you become," which is the same lever every successful
Roblox power-fantasy thumbnail pulls (Blade Ball, Pet Sim, Anime
Fighters all run some version of this).

Rotate these three across the marquee slots and swap #1's roster
characters periodically once new Brainrots ship — a thumbnail refresh is
one of the cheapest CTR levers available post-launch and costs nothing but
re-render time.

---

## 4. Monetization Plan

### Relative positioning: Game Passes

| Pass | Role | Suggested price band | Why |
|---|---|---|---|
| **VIP** | Gateway / impulse buy | ~150-249 Robux | Cheapest pass, broad perk bundle (small daily Gems stipend, VIP chat tag, minor spawn perk). Its job is to convert a player's *first* purchase ever — low friction, low regret. |
| **Extra Inventory Slots** | Evergreen QoL, repeatable | ~99-199 Robux per tier, stackable/tiered | Classic low-risk purchase — doesn't touch power balance, just collection headroom. Good for players who've hatched a lot and are getting inventory-full nags; sell it contextually (prompt when inventory is >90% full, not cold).
| **Double Coins** | Mid-tier grind-skip | ~299-399 Robux | Strong impulse buy for players already engaged (they've felt the grind by the time they'd consider this). Doesn't affect PvP power directly, only pace. |
| **Double Luck** | Highest-value pass, closest to "whale-adjacent" | ~399-499 Robux | This is the one that touches the core rarity chase, so it reads as the most valuable pass and should be priced above Double Coins. **Flag:** see pay-to-win note below before finalizing this one. |

### Relative positioning: Developer Products

- **Coins packs** — the true impulse tier. 3-4 sizes, smallest around
  79-99 Robux specifically to clear the "first purchase ever" psychological
  hurdle cheaply. These exist to convert *volume*, not revenue-per-user.
- **Gems packs** — the whale tier, since Gems buy Secret Eggs directly (the
  single strongest chase-motivator in the game). Use a classic 4-5 tier
  ladder with one deliberately-marked "Best Value" tier positioned
  upper-middle (not the top tier) — that's the slot that converts best in
  practice; the top "mega" tier exists for max-spenders and shouldn't be
  the one advertised in the shop's default view.

**Pricing philosophy in one line:** the pass ladder should escalate with
*how close the perk sits to the rarity chase* — inventory slots (no power
effect) cheapest, Double Luck (directly shifts rarity odds) most expensive
of the passes — and Gems, not Coins, should be the product line carrying
the whale tier, because Gems are the direct path to Secret Eggs.

### ⚠️ Pay-to-win tension — flag this, don't bury it

Because equipped rarity directly determines CTF ability power (this is
intentional per `BRAINROT_ROSTER.md`'s ability power budget — Legendary
abilities are meaningfully stronger than Common ones), **Double Luck and
Gems packs are not purely cosmetic monetization — they're adjacent to
competitive power.** That's a legitimate design tension, not necessarily a
mistake, but it needs to be managed on purpose rather than ignored:

- Keep pushing the build team to preserve a real skill floor (dodging,
  positioning, timing an ability) so a Common-equipped free player can
  still out-play a Legendary-equipped payer — the roster doc's own "Secret
  is mobility not raw power" design principle is the right instinct; extend
  that discipline to Legendary vs. Epic too if playtesting shows lopsided
  win rates.
- Watch F2P retention specifically in CTF once live-ops data exists. If
  free players are getting stomped and churning, the fix is balance
  tuning or matchmaking, not softening Double Luck's marketing — don't
  paper over a real balance problem with copy.
- Never market Double Luck or Gems with language like "get the strongest
  Brainrots" or "win every match" — market them as *faster*, not
  *required*. That's the line between acceptable monetization framing and
  predatory pay-to-win advertising.

### Compliance — non-negotiable

Roblox requires **published, real odds** for any randomized virtual item
mechanic — that's every Egg in this game. The odds table already exists in
`BRAINROT_ROSTER.md`; it must be surfaced in the actual hatch UI (not just
this doc) and ideally mirrored on the store page description. This isn't
optional and isn't a "nice to have" — flag it to whoever owns the Egg UI if
the odds aren't visibly displayed before a player spends currency.

### Limited-time events (2-3 ideas, and where the line is)

1. **Rotating "Secret Egg Spotlight" weekend.** Pick one Secret/Legendary
   Brainrot, give it a real, disclosed odds boost for 48-72 hours, promote
   it with an in-game countdown and matching social posts. This is
   legitimate urgency because the odds change is real and published — not
   a trick. **Never** use a countdown that resets or a "spotlight" that
   quietly reverts without the boost actually applying — that crosses into
   dark pattern territory immediately.
2. **Seasonal CTF ladder.** A 2-4 week season with a win-based leaderboard;
   top finishers earn an **exclusive cosmetic recolor** of an existing
   Brainrot (visual only, no stat difference) rather than a new
   stronger unit. This drives daily engagement through skill/time
   investment, not spend — genuinely the healthiest kind of event this
   game can run, and it also gives content creators a fresh clip reason
   every few weeks.
3. **Double Coins weekend synced to a content push.** Time a Double Coins
   (not Double Luck — keep the spend-adjacent lever out of hype weekends)
   event to land the same week as a new Brainrot reveal or a creator
   video push, so paid acquisition and organic hype reinforce each other
   instead of competing for the same calendar slot.

**Explicitly avoid:** mystery/bundle purchases that obscure per-item odds
inside a multi-item pack, "near-miss" hatch animations engineered to feel
like a near-Secret when the roll was never close (a known slot-machine
manipulation pattern), push notifications that manufacture urgency aimed at
lapsed young players ("your Brainrot expires in 1 hour!" spam), and any
event framing that implies a paid pass is required to be competitive. All
of these are common in the genre and all of them are the kind of thing that
gets a game flagged in press coverage or by Roblox trust & safety — skip
them, the events above convert fine without them.

---

## 5. Launch & Growth Strategy — First 90 Days

### Pre-launch (weeks -3 to 0)

- **Clip the two most "clippable" moments now**, before there's even a
  public game page: the hatch-reveal (egg cracking, light burst, rarity
  color flash) and a CTF ability play (Magma Slam's AoE stun, Rail
  Charge's knockback, Starlight Warp's teleport — pick whichever records
  cleanest). These are the two moments this game can generate on a loop
  without any editing skill required — lean on that.
- Post 15-30s vertical cuts on TikTok/Shorts/Reels 2-3x/week, riding
  existing trending "brainrot"-adjacent audio. Don't link the game yet —
  this phase is pure aesthetic/vibe seeding, not conversion.
- Stand up the Discord early: a `#roster-reveal` channel that drip-feeds
  one Brainrot from `BRAINROT_ROSTER.md` every few days (16 characters is
  enough for a full pre-launch content calendar on its own), a
  `#hatch-reveal` channel where the team posts its own test pulls to
  build anticipation for the odds/rarity system.
- Get the Roblox game page live early (even pre-full-launch, as
  "in development") — search indexing and page-age both factor into
  discovery, so don't wait for feature-complete to claim the URL.

### Launch week

- Roblox's discovery algorithm weights **early concurrent players and
  session length** heavily for new releases — the highest-leverage single
  move this week is coordinating a "launch hour" where Discord members and
  any seeded creators all jump in at the same time, rather than trickling
  traffic over days. A CCU spike in hour one does more for the algorithm
  than the same total players spread over a week.
- Discord additions for launch: a `#flex-your-pull` channel (players
  posting their own hatch screenshots — free UGC, zero cost to run), a
  bug-report channel with a small in-game Coins reward for the first
  report of each confirmed bug (cheap goodwill, real QA signal).
- **Creator seeding list — profile, not names** (don't fabricate handles):
  target **micro/mid Roblox-and-brainrot-trend creators in the roughly
  5K-150K follower range** whose recent posts are already hatch-reveal
  reactions, Roblox PvP clips, or general "brainrot" trend content — and
  filter on *engagement rate*, not raw follower count (a 20K-follower
  account averaging 50K+ views per video is worth more than a stagnant
  200K account). Reach out with a free Gems code and an ask for an honest
  first-impressions video, not a scripted read — this niche's audience can
  tell the difference and punishes obvious ad reads. Budget for **10-20
  micro-creators rather than one large one** — this mirrors how the
  brainrot trend itself actually spread (many small creators piling onto
  the same aesthetic near-simultaneously, not one mega-influencer moment).

### Ongoing (weeks 3-12+)

- **Weekly content cadence tied to new Brainrot drops**: tease art Monday,
  ship the character in-game Friday. This does double duty — it's a
  built-in reason for lapsed players to check back weekly, and it refills
  the TikTok pipeline without needing new "ideas," just the next roster
  entry.
- Run the seasonal CTF ladder (Section 4) on a repeating 3-4 week cycle
  once the first one proves out — it's the retention engine that doesn't
  cost anything to keep running.
- **Referral/friend-invite hook — this does not exist yet.** I checked
  `Constants.lua`'s `REMOTE_NAMES` and there's no invite/referral remote
  defined anywhere in the current systems. This is one of the highest-ROI
  growth loops in the genre (Blox Fruits, Pet Simulator, and Brookhaven all
  run some version of "invite a friend, both get a reward") and it's
  currently missing. **Recommend the build team add**: a simple
  server-validated "both players get X Coins / a guaranteed Rare Egg once
  the invited friend reaches level/hatch-count N" — gate the reward on an
  actual play milestone, not just a join, or it'll get farmed with alt
  accounts. This is a feature request out of this doc, not something
  marketing can ship alone.
- Keep re-cutting Thumbnail concept #1 (Section 3) with updated roster
  members every few weeks — cheapest CTR lever available post-launch.
