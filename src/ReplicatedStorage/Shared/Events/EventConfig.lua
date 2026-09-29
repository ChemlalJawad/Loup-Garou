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

return EventConfig
