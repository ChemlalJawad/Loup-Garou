--!strict
-- Pure data: the quest pool + pure helper functions. No DataService/Net
-- access here (matches the EggConfig convention) so both QuestService
-- (server, authoritative progress/claim) and QuestUI (client, display) can
-- require this safely.
--
-- Quest *types* are a small trackable-event enum rather than bespoke logic
-- per quest, so QuestService can drive every quest's progress from one
-- generic diff-the-profile loop. See QuestService.lua for how each type is
-- fed (mostly `profile.Stats` deltas, `HatchRarity` from `profile.Index`,
-- `ReachLevel` from `profile.Level`).

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local QuestConfig = {}

export type QuestType =
	"HatchEggs" -- profile.Stats.EggsHatched delta
	| "HatchRarity" -- profile.Index delta, filtered to Rarity-or-better
	| "SellBrainrots" -- profile.Stats.BrainrotsSold delta
	| "CaptureFlags" -- profile.Stats.FlagCaptures delta
	| "ReturnFlags" -- profile.Stats.FlagReturns delta
	| "TagPlayers" -- profile.Stats.Tags delta
	| "WinRounds" -- profile.Stats.RoundsWon delta
	| "PlayRounds" -- profile.Stats.RoundsPlayed delta
	| "EarnCoins" -- profile.Stats.CoinsEarned delta
	| "ReachLevel" -- profile.Level, absolute (not delta)

export type QuestTier = "Daily" | "Weekly"

export type QuestReward = {
	Coins: number?,
	Gems: number?,
	XP: number?,
}

export type QuestDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Type: QuestType,
	Target: number,
	Reward: QuestReward,
	Tier: QuestTier,
	-- Only meaningful (and required) for Type == "HatchRarity": the minimum
	-- rarity that counts, e.g. Rarity = "Epic" means "Epic or better".
	Rarity: string?,
}

-- === The pool ===============================================================
-- Single source of truth; Pool/DailyOrder/WeeklyOrder below are all derived
-- from this list so there's no risk of the derived tables drifting from it.

local questList: { QuestDefinition } = {
	-- Daily --------------------------------------------------------------
	{
		Id = "Daily_HatchEggs_5",
		Name = "Crack a Few",
		Description = "Hatch 5 eggs of any kind.",
		Type = "HatchEggs",
		Target = 5,
		Reward = { Coins = 200 },
		Tier = "Daily",
	},
	{
		Id = "Daily_HatchEggs_15",
		Name = "Hatchery Regular",
		Description = "Hatch 15 eggs of any kind.",
		Type = "HatchEggs",
		Target = 15,
		Reward = { Coins = 550 },
		Tier = "Daily",
	},
	{
		Id = "Daily_HatchRarity_Rare_3",
		Name = "Rare Finds",
		Description = "Hatch 3 Brainrots that are Rare or better.",
		Type = "HatchRarity",
		Target = 3,
		Rarity = "Rare",
		Reward = { Coins = 400 },
		Tier = "Daily",
	},
	{
		Id = "Daily_HatchRarity_Epic_1",
		Name = "Epic Pull",
		Description = "Hatch 1 Brainrot that is Epic or better.",
		Type = "HatchRarity",
		Target = 1,
		Rarity = "Epic",
		Reward = { Coins = 750, Gems = 5 },
		Tier = "Daily",
	},
	{
		Id = "Daily_SellBrainrots_5",
		Name = "Tidy Up",
		Description = "Sell 5 Brainrots.",
		Type = "SellBrainrots",
		Target = 5,
		Reward = { Coins = 250 },
		Tier = "Daily",
	},
	{
		Id = "Daily_SellBrainrots_10",
		Name = "Clear the Shelves",
		Description = "Sell 10 Brainrots.",
		Type = "SellBrainrots",
		Target = 10,
		Reward = { Coins = 450 },
		Tier = "Daily",
	},
	{
		Id = "Daily_CaptureFlags_2",
		Name = "Flag Runner",
		Description = "Capture the enemy flag 2 times.",
		Type = "CaptureFlags",
		Target = 2,
		Reward = { Coins = 300 },
		Tier = "Daily",
	},
	{
		Id = "Daily_ReturnFlags_3",
		Name = "Home Defense",
		Description = "Return your team's flag 3 times.",
		Type = "ReturnFlags",
		Target = 3,
		Reward = { Coins = 250 },
		Tier = "Daily",
	},
	{
		Id = "Daily_TagPlayers_5",
		Name = "Quick Tags",
		Description = "Tag 5 enemy players.",
		Type = "TagPlayers",
		Target = 5,
		Reward = { Coins = 200 },
		Tier = "Daily",
	},
	{
		Id = "Daily_WinRounds_1",
		Name = "First Victory",
		Description = "Win 1 CTF round.",
		Type = "WinRounds",
		Target = 1,
		Reward = { Coins = 350 },
		Tier = "Daily",
	},
	{
		Id = "Daily_PlayRounds_3",
		Name = "Get In There",
		Description = "Play 3 CTF rounds.",
		Type = "PlayRounds",
		Target = 3,
		Reward = { Coins = 200 },
		Tier = "Daily",
	},
	{
		Id = "Daily_EarnCoins_500",
		Name = "Coin Collector",
		Description = "Earn 500 Coins from any source.",
		Type = "EarnCoins",
		Target = 500,
		Reward = { Gems = 5 },
		Tier = "Daily",
	},

	-- Weekly ---------------------------------------------------------------
	{
		Id = "Weekly_HatchEggs_100",
		Name = "Hatch Machine",
		Description = "Hatch 100 eggs of any kind.",
		Type = "HatchEggs",
		Target = 100,
		Reward = { Coins = 3000 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_HatchRarity_Epic_5",
		Name = "Epic Streak",
		Description = "Hatch 5 Brainrots that are Epic or better.",
		Type = "HatchRarity",
		Target = 5,
		Rarity = "Epic",
		Reward = { Coins = 2500 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_HatchRarity_Legendary_1",
		Name = "Legendary Hunt",
		Description = "Hatch 1 Brainrot that is Legendary or better.",
		Type = "HatchRarity",
		Target = 1,
		Rarity = "Legendary",
		Reward = { Gems = 50 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_SellBrainrots_25",
		Name = "Inventory Purge",
		Description = "Sell 25 Brainrots.",
		Type = "SellBrainrots",
		Target = 25,
		Reward = { Coins = 1500 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_CaptureFlags_15",
		Name = "Flag Hoarder",
		Description = "Capture the enemy flag 15 times.",
		Type = "CaptureFlags",
		Target = 15,
		Reward = { Coins = 2000 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_ReturnFlags_20",
		Name = "Iron Defense",
		Description = "Return your team's flag 20 times.",
		Type = "ReturnFlags",
		Target = 20,
		Reward = { Coins = 1500 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_TagPlayers_40",
		Name = "Bounty Hunter",
		Description = "Tag 40 enemy players.",
		Type = "TagPlayers",
		Target = 40,
		Reward = { Coins = 1800 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_WinRounds_10",
		Name = "Champion",
		Description = "Win 10 CTF rounds.",
		Type = "WinRounds",
		Target = 10,
		Reward = { Coins = 3000, Gems = 20 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_PlayRounds_20",
		Name = "Season Regular",
		Description = "Play 20 CTF rounds.",
		Type = "PlayRounds",
		Target = 20,
		Reward = { Coins = 1500 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_EarnCoins_5000",
		Name = "Big Earner",
		Description = "Earn 5,000 Coins from any source.",
		Type = "EarnCoins",
		Target = 5000,
		Reward = { Gems = 30 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_ReachLevel_10",
		Name = "Rising Star",
		Description = "Reach player level 10.",
		Type = "ReachLevel",
		Target = 10,
		Reward = { Coins = 1000 },
		Tier = "Weekly",
	},
	{
		Id = "Weekly_ReachLevel_25",
		Name = "Veteran",
		Description = "Reach player level 25.",
		Type = "ReachLevel",
		Target = 25,
		Reward = { Gems = 40 },
		Tier = "Weekly",
	},
}

local pool: { [string]: QuestDefinition } = {}
local dailyOrder: { string } = {}
local weeklyOrder: { string } = {}
for _, def in questList do
	pool[def.Id] = def
	if def.Tier == "Daily" then
		table.insert(dailyOrder, def.Id)
	else
		table.insert(weeklyOrder, def.Id)
	end
end

QuestConfig.Pool = pool
QuestConfig.DailyOrder = dailyOrder
QuestConfig.WeeklyOrder = weeklyOrder

function QuestConfig.GetQuest(questId: string): QuestDefinition?
	return pool[questId]
end

-- True when `actual` rarity is at-or-above `threshold` rarity in
-- Constants.RARITY_ORDER, e.g. RarityMeetsOrExceeds("Legendary", "Epic") ==
-- true. Used for HatchRarity quests ("hatch 3 Epic or better").
function QuestConfig.RarityMeetsOrExceeds(actual: string, threshold: string): boolean
	local actualIndex = table.find(Constants.RARITY_ORDER, actual)
	local thresholdIndex = table.find(Constants.RARITY_ORDER, threshold)
	if not actualIndex or not thresholdIndex then
		return false
	end
	return actualIndex >= thresholdIndex
end

-- Deterministic Fisher-Yates shuffle seeded by `seed`, returning the first
-- `count` ids from `order`. Determinism matters here: the same
-- (player, day) seed must always produce the same set, so a player who
-- rejoins mid-day sees the identical daily quests rather than a reroll.
local function rollSet(order: { string }, seed: number, count: number): { string }
	local shuffled = table.clone(order)
	local rng = Random.new(seed)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local result: { string } = {}
	local n = math.min(count, #shuffled)
	for i = 1, n do
		result[i] = shuffled[i]
	end
	return result
end

-- Pure: picks `count` daily quest ids deterministically from `seed`. Callers
-- (QuestService) derive `seed` from (player UserId, UTC day index) so the
-- result is stable for a given player on a given day.
function QuestConfig.RollDailySet(seed: number, count: number): { string }
	return rollSet(dailyOrder, seed, count)
end

-- Pure: same idea as RollDailySet but for the weekly pool. Callers derive
-- `seed` from (player UserId, UTC week index).
function QuestConfig.RollWeeklySet(seed: number, count: number): { string }
	return rollSet(weeklyOrder, seed, count)
end

return QuestConfig
