--!strict
-- World events. Currently: Coin Rain - every few minutes, coins pour down
-- over the Central Plaza for a short window and everyone races to grab them.
--
-- Why it's here: a scheduled, shared moment pulls the whole server into one
-- place at once. For a young audience that's the social glue ("coin rain in
-- 10 seconds, come to the plaza!"), and it gives players who are behind a
-- guaranteed, skill-free way to catch up - nobody leaves empty-handed.

local EventConfig = {}

export type Coin = {
	Id: number,
	Position: Vector3,
}

export type CoinRainPayload = {
	EventId: string,
	Kind: string, -- "CoinRain"
	EndsAt: number, -- workspace:GetServerTimeNow() when it ends
	Coins: { Coin },
}

EventConfig.COIN_RAIN = {
	Zone = "Hub",
	FirstDelay = 90, -- seconds after server start
	Interval = 6 * 60, -- between the end of one rain and the next warning
	Warning = 10, -- seconds of "coin rain incoming" heads-up
	Duration = 45,
	CoinCount = 70,
	EdgeMargin = 8, -- keep coins off the zone's outer edge
	AvoidCenterRadius = 13, -- the landmark fountain sits in the middle
	HoverHeight = 3.5, -- above the ground, at grab height
	-- Coins per pickup = Base + Level * PerLevel (then EconomyService
	-- multipliers). Scales with level so it stays worth running for.
	BaseValue = 12,
	PerLevel = 2,
	ClientPickupRadius = 5,
	ServerPickupRadius = 14, -- looser, to absorb latency
	MaxPickupsPerSecond = 15, -- per player; a fast runner won't hit it, a script would
}

-- Lucky Rainbow: a "weather" window (the genre's best-loved event type) where
-- a rainbow arcs over the map and Parade Brainrots are twice as likely to
-- arrive mutated. Nobody has to be anywhere or do anything special to
-- benefit, so it's pure good news for everyone on the server.
--
-- Broadcast as a Workspace attribute holding the server time it ends at:
-- attributes replicate to every client (including late joiners) for free,
-- and any server script can check it without depending on EventService.
EventConfig.LUCKY_RAINBOW = {
	FirstDelay = 5 * 60,
	Interval = 14 * 60, -- between the end of one rainbow and the next
	Duration = 150,
	MutationMultiplier = 2,
	Attribute = "LuckyRainbowEndsAt",
}

function EventConfig.IsLuckyRainbow(serverNow: number): boolean
	local endsAt = workspace:GetAttribute(EventConfig.LUCKY_RAINBOW.Attribute)
	return type(endsAt) == "number" and serverNow < endsAt
end

-- Mutation chances scaled up while the rainbow is out. Returns the input
-- table untouched otherwise, so the common case allocates nothing.
function EventConfig.ApplyLuck(chances: { [string]: number }, serverNow: number): { [string]: number }
	if not EventConfig.IsLuckyRainbow(serverNow) then
		return chances
	end
	local boosted = {}
	for mutationId, chance in chances do
		boosted[mutationId] = math.min(chance * EventConfig.LUCKY_RAINBOW.MutationMultiplier, 0.5)
	end
	return boosted
end

return EventConfig
