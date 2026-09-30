--!strict
-- Brainrot Parade (red carpet) tuning + the pure geometry both sides share.
--
-- The genre's signature mechanic: Brainrots walk down a red carpet one after
-- another; you buy the one you want before it reaches the end and walks off.
-- It turns shopping into a live, social moment ("a RAINBOW just spawned -
-- run!") instead of a menu.
--
-- Networking model: the server decides *what* spawns and *when* (SpawnedAt,
-- in shared server time). Where a walker is at any moment is a pure function
-- of that time (PositionAt below), so clients animate walkers locally and
-- the server validates purchases against the same function - no per-frame
-- position replication at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Mutations = require(ReplicatedStorage.Shared.Brainrots.Mutations)

local ParadeConfig = {}

export type Walker = {
	Uid: string,
	Id: string,
	Rarity: string,
	Mutation: string?,
	Price: number,
	SpawnedAt: number, -- workspace:GetServerTimeNow() at spawn
	Duration: number, -- seconds from start gate to end gate
}

ParadeConfig.SPAWN_INTERVAL = 3.5
-- Slow enough that a young player can run alongside, read the label and
-- decide; fast enough that the carpet always looks alive.
ParadeConfig.WALK_SECONDS = 45
ParadeConfig.MAX_ACTIVE = 14

-- Client prompt reach vs the server's validation radius. The server allows
-- more slack than the prompt to absorb latency and the walker moving a few
-- studs between the tap and the request arriving.
ParadeConfig.PROMPT_DISTANCE = 12
ParadeConfig.BUY_RADIUS = 22
ParadeConfig.BUY_COOLDOWN = 0.35 -- per player, anti double-tap / spam

-- Clients skip animating the carpet when the player is further than this
-- from it (they can't see it anyway); walkers snap to the right spot on
-- approach because position is a function of time.
ParadeConfig.RENDER_DISTANCE = 300
ParadeConfig.MODEL_SCALE = 1.35 -- a touch larger than followers: the carpet is a showcase

-- What walks down the carpet. Friendlier odds than eggs at the top end -
-- you still have to afford it, so rarity is gated by price, not luck alone.
local rarityWeights: { [string]: number } = {
	Common = 62,
	Rare = 26,
	Epic = 9,
	Legendary = 2.7,
	Secret = 0.3,
}
ParadeConfig.RarityWeights = rarityWeights
ParadeConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Secret" }

local basePrice: { [string]: number } = {
	Common = 150,
	Rare = 900,
	Epic = 5000,
	Legendary = 30000,
	Secret = 180000,
}
ParadeConfig.BasePrice = basePrice

-- Mutation odds match what players know from the genre by day; night adds
-- the Galaxy variant and doubles Rainbow, which is what makes staying up
-- through the day/night cycle worth it.
local dayChances: { [string]: number } = { Gold = 0.10, Diamond = 0.05, Rainbow = 0.01 }
local nightChances: { [string]: number } = { Gold = 0.10, Diamond = 0.06, Galaxy = 0.04, Rainbow = 0.02 }
ParadeConfig.MutationChancesDay = dayChances
ParadeConfig.MutationChancesNight = nightChances

-- Spawns worth a server-wide shout-out.
ParadeConfig.AnnounceRarities = { Legendary = true, Secret = true } :: { [string]: boolean }
ParadeConfig.AnnounceMutations = { Rainbow = true, Galaxy = true } :: { [string]: boolean }

-- Geometry -------------------------------------------------------------------
--
-- The carpet runs west -> east along the south half of the Parade zone, so
-- the north half (where the path from the Hall of Fame arrives) stays open
-- for players to stand and shop. ParadeZone builds the carpet from these
-- same numbers.

ParadeConfig.CARPET_WIDTH = 10
ParadeConfig.CARPET_TOP_Y = WorldLayout.GroundY + 0.6
ParadeConfig.CARPET_Z_OFFSET = -18 -- from the zone centre, toward the south edge
ParadeConfig.CARPET_END_MARGIN = 12 -- from each short edge of the zone

function ParadeConfig.CarpetEndpoints(): (Vector3, Vector3)
	local zone = WorldLayout.Get("Parade")
	local z = zone.Center.Z + ParadeConfig.CARPET_Z_OFFSET
	local halfX = zone.Size.X / 2 - ParadeConfig.CARPET_END_MARGIN
	local startPoint = Vector3.new(zone.Center.X - halfX, ParadeConfig.CARPET_TOP_Y, z)
	local endPoint = Vector3.new(zone.Center.X + halfX, ParadeConfig.CARPET_TOP_Y, z)
	return startPoint, endPoint
end

-- Progress along the carpet (0 = start gate, 1 = end gate), unclamped so
-- callers can tell "not started" (< 0) and "already left" (>= 1) apart.
function ParadeConfig.ProgressAt(walker: Walker, serverTime: number): number
	return (serverTime - walker.SpawnedAt) / walker.Duration
end

function ParadeConfig.PositionAt(walker: Walker, serverTime: number): Vector3
	local startPoint, endPoint = ParadeConfig.CarpetEndpoints()
	local alpha = math.clamp(ParadeConfig.ProgressAt(walker, serverTime), 0, 1)
	return startPoint:Lerp(endPoint, alpha)
end

function ParadeConfig.PriceFor(rarity: string, mutation: string?): number
	local base = basePrice[rarity] or basePrice.Common
	-- Round to a friendly number: 1,350 reads better than 1,347.
	return math.floor(base * Mutations.PriceMultiplier(mutation) / 10 + 0.5) * 10
end

function ParadeConfig.RollRarity(rng: Random): string
	local total = 0
	for _, rarity in ParadeConfig.RarityOrder do
		total += rarityWeights[rarity] or 0
	end
	local roll = rng:NextNumber() * total
	for _, rarity in ParadeConfig.RarityOrder do
		roll -= rarityWeights[rarity] or 0
		if roll < 0 then
			return rarity
		end
	end
	return "Common"
end

-- Thousands separators for prices shown to players.
function ParadeConfig.FormatCoins(amount: number): string
	local digits = tostring(math.floor(amount))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return ParadeConfig
