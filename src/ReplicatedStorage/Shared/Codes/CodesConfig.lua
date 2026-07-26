--!strict
-- Promo codes for social/marketing pushes (YouTube/TikTok captions, Discord
-- announcements, X posts). This is the file whoever runs the game's socials
-- edits when they want to drop a new code - no other file needs to change.
--
-- HOW TO ADD A CODE AT LAUNCH (or any time after):
--   1. Add an entry to `codes` below. `Code` is matched case-insensitively
--      (both sides are normalized to uppercase by CodesService), so write it
--      however reads best on screen - "SpaghettOro" or "SPAGHETTORO" both work.
--   2. Give it a Reward bundle (Coins/Gems/XP - same shape EconomyService.
--      AwardBundle takes). Add BoostName/BoostSeconds for a timed boost on
--      top (BoostName must match an EconomyService.BOOST_* constant, e.g.
--      "Coins2x", "XP2x", "Luck2x").
--   3. Optionally set ExpiresAt to a unix timestamp (e.g. os.time() computed
--      once and hardcoded, or build it with os.time({year=...,...})) so the
--      code stops working after a campaign ends. Leave nil for a code that
--      never expires.
--   4. That's it - CodesService picks it up on the next server start /
--      publish. No redeploy of any other system required.
--
-- ON GLOBAL CAPS: there is deliberately no "first N players" / MaxRedemptions
-- style global cap here. Per-player one-time redemption IS enforced (via
-- profile.CodesRedeemed in CodesService), but a true *global* cap can't be
-- honoured from per-player data alone - it needs a shared DataStore counter
-- with UpdateAsync retry/contention handling, which is real additional work,
-- not a config toggle. Don't set a "MaxRedemptions" field here expecting it
-- to do anything; it would be a lie. If a global cap is needed later, that's
-- new CodesService work, flagged for whoever picks it up next.

local CodesConfig = {}

export type CodeReward = {
	Coins: number?,
	Gems: number?,
	XP: number?,
}

export type CodeDefinition = {
	Code: string, -- written in whatever case reads best; matched case-insensitively
	Reward: CodeReward,
	BoostName: string?,
	BoostSeconds: number?,
	ExpiresAt: number?, -- unix timestamp; nil = never expires
}

local codes: { CodeDefinition } = {
	{ Code = "BRAINROT", Reward = { Coins = 1000 } },
	{ Code = "RELEASE", Reward = { Coins = 2500, Gems = 25 } },
	{ Code = "SPAGHETTORO", Reward = { Gems = 50 } },
	{ Code = "LIKE1K", Reward = { Coins = 1500 }, BoostName = "Coins2x", BoostSeconds = 30 * 60 },
	{ Code = "TUALETI", Reward = { Coins = 5000 } },
	{ Code = "SIGMA", Reward = { Coins = 1000, Gems = 10 }, BoostName = "Luck2x", BoostSeconds = 15 * 60 },
}

CodesConfig.Codes = codes

local byCode: { [string]: CodeDefinition } = {}
for _, def in codes do
	byCode[string.upper(def.Code)] = def
end

-- Case-insensitive lookup: normalizes `codeString` to uppercase before
-- indexing, same normalization CodesService applies before calling this.
function CodesConfig.Find(codeString: string): CodeDefinition?
	return byCode[string.upper(codeString)]
end

return CodesConfig
