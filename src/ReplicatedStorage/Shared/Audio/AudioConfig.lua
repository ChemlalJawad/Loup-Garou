--!strict
-- Central sound-cue and music-track registry for the whole game. Every other
-- system plays audio by *id* (a string key in `AudioConfig.Cues` /
-- `AudioConfig.Music`) — nobody hardcodes a `rbxassetid://` string outside
-- this file.
--
-- =============================================================================
-- READ THIS BEFORE PUBLISHING
-- =============================================================================
-- This build sandbox has no asset-upload pipeline and no way to verify a
-- `rbxassetid://` number actually points at the sound it claims to be, so
-- every `SoundId` below is intentionally left as an empty string `""` with a
-- `-- TODO: upload/pick a real asset id` comment describing the sound that
-- belongs there. An empty `SoundId` is a supported, permanent-until-filled-in
-- state: `AudioService`/`AudioController` treat it as "no-op, play nothing" —
-- never as an error. The game is fully playable (silently) today.
--
-- Before shipping:
--   1. Upload or source-license real audio for each cue (Roblox's Creator
--      Marketplace / your own uploads under the experience's Audio Library).
--   2. Fill in `SoundId = "rbxassetid://<id>"` for the cues you care about.
--      You do not have to fill in all of them — anything left empty stays
--      silent forever, gracefully.
--   3. Search this file for "TODO: upload" to find every remaining gap.
--
-- Do NOT invent asset ids. A made-up id either fails to load (harmless) or,
-- worse, resolves to someone else's unrelated/inappropriate uploaded audio in
-- a *shipped* game (harmful). If you are not certain an id is a real, correct
-- Roblox built-in sound, leave the placeholder.
-- =============================================================================

local AudioConfig = {}

export type SoundCue = {
	SoundId: string, -- "" = placeholder, no-op until filled in
	Volume: number, -- 0-1
	PlaybackSpeed: number?, -- fixed pitch, or omit and use PitchRange
	PitchRange: { Min: number, Max: number }?, -- randomized pitch for variation; overrides PlaybackSpeed when present
	Description: string, -- what to source/upload: length, character, mood
}

export type MusicTrack = {
	SoundId: string,
	Volume: number,
	Looped: boolean,
	Description: string,
}

-- Shorthand so every entry below reads as one line instead of five.
local function cue(soundId: string, volume: number, description: string, extra: { PlaybackSpeed: number?, PitchRange: { Min: number, Max: number }? }?): SoundCue
	local entry: SoundCue = {
		SoundId = soundId,
		Volume = volume,
		Description = description,
	}
	if extra then
		entry.PlaybackSpeed = extra.PlaybackSpeed
		entry.PitchRange = extra.PitchRange
	end
	return entry
end

local cues: { [string]: SoundCue } = {}

-- === UI ======================================================================
cues.UIClick = cue("", 0.5, "very short, dry click/tap, ~0.05-0.1s, for button presses", { PitchRange = { Min = 0.97, Max = 1.03 } })
cues.UIOpen = cue("", 0.5, "soft upward whoosh/swell, ~0.2s, for opening a panel/modal")
cues.UIClose = cue("", 0.4, "soft downward whoosh, ~0.15s, for closing a panel/modal")

-- === Economy =================================================================
cues.Purchase = cue("", 0.6, "satisfying cash/coin register chime, ~0.4s, successful purchase")
cues.PurchaseFail = cue("", 0.5, "short low buzz/denied tone, ~0.25s, purchase failed (insufficient funds etc.)")
cues.CoinReward = cue("", 0.5, "bright coin/sparkle tick, ~0.2s, for +Coins popups", { PitchRange = { Min = 0.95, Max = 1.08 } })
cues.LevelUp = cue("", 0.7, "triumphant rising fanfare, ~1s, player leveled up")
cues.Rebirth = cue("", 0.8, "big ascending magical swell, ~1.5s, rebirth performed")

-- === Eggs / hatching =========================================================
cues.EggCrack = cue("", 0.6, "crunchy crack/shell-break hit, ~0.3s, egg starting to hatch")

-- Hatch reveal escalates with rarity — this IS the point: Common should feel
-- almost throwaway, Secret should feel like a jackpot.
cues.HatchReveal_Common = cue("", 0.45, "small plain pop/chime, ~0.3s, common-rarity reveal")
cues.HatchReveal_Rare = cue("", 0.5, "brighter double-note chime, ~0.4s, rare-rarity reveal")
cues.HatchReveal_Epic = cue("", 0.6, "shimmering rising arpeggio, ~0.6s, epic-rarity reveal")
cues.HatchReveal_Legendary = cue("", 0.7, "bold horn/synth hit with sparkle tail, ~0.8s, legendary-rarity reveal")
cues.HatchReveal_Secret = cue("", 0.85, "full jackpot fanfare with crowd-hype swell, ~1.2s, secret-rarity reveal")

-- === Quests / Daily / Codes ==================================================
cues.QuestComplete = cue("", 0.6, "cheerful checkmark ding, ~0.4s, quest completed")
cues.DailyClaim = cue("", 0.6, "gift-unwrap sparkle, ~0.5s, daily reward claimed")
cues.CodeRedeem = cue("", 0.6, "confirmation chime, ~0.4s, promo code redeemed successfully")

-- === CTF ======================================================================
cues.FlagTaken = cue("", 0.65, "sharp alert stinger, ~0.4s, a flag was picked up")
cues.FlagCaptured = cue("", 0.8, "victorious horn hit, ~0.7s, a flag was captured/scored")
cues.FlagReturned = cue("", 0.55, "neutral positive chime, ~0.35s, a flag was returned to its stand")
cues.PlayerTagged = cue("", 0.6, "impact thud/hit-stop punch, ~0.2s, a player was tagged")
cues.AbilityUsed = cue("", 0.55, "whoosh/energy-release cast sound, ~0.35s, CTF ability activated", { PitchRange = { Min = 0.95, Max = 1.05 } })
cues.PowerupCollected = cue("", 0.5, "bright pickup blip, ~0.25s, powerup collected")
cues.RoundStart = cue("", 0.7, "countdown/start klaxon, ~0.6s, CTF round starting")
cues.RoundWin = cue("", 0.8, "victory fanfare, ~1.2s, round won")
cues.RoundLose = cue("", 0.6, "somber short sting, ~0.8s, round lost")

AudioConfig.Cues = cues

-- === Music ====================================================================
local music: { [string]: MusicTrack } = {}

music.Hub = {
	SoundId = "",
	Volume = 0.25,
	Looped = true,
	Description = "TODO: upload/pick a real asset id - laid-back, playful loop for the central hub/plaza, ~2min seamless loop",
}
music.Arena = {
	SoundId = "",
	Volume = 0.3,
	Looped = true,
	Description = "TODO: upload/pick a real asset id - higher-energy combat loop for the CTF arena, ~2min seamless loop",
}

AudioConfig.Music = music

-- Returns the cue table for `cueId`, or nil if the id is unknown. Callers
-- should treat "unknown id" and "empty SoundId" both as safe no-ops.
function AudioConfig.GetCue(cueId: string): SoundCue?
	return cues[cueId]
end

function AudioConfig.GetMusic(trackId: string): MusicTrack?
	return music[trackId]
end

-- Given a rarity string (Constants.RARITY_ORDER), returns the matching
-- HatchReveal_* cue id, falling back to Common for unknown rarities so a
-- typo'd rarity never throws.
function AudioConfig.HatchRevealCueId(rarity: string): string
	local id = "HatchReveal_" .. rarity
	if cues[id] then
		return id
	end
	return "HatchReveal_Common"
end

return AudioConfig
