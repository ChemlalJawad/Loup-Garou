--!strict
-- Rotating daily/weekly objectives across all three pillars (hatching, CTF,
-- economy). Owns `profile.Quests` and `profile.QuestsRefreshedAt`.
--
-- THE TRACKING PROBLEM: EggService and CTFService are owned by other agents
-- and must not be edited, so this service cannot ask them to call in when
-- something quest-relevant happens. Instead it observes DataService, which
-- every system already funnels through:
--   - `DataService.ProfileChanged` fires (player, profile) after every
--     mutation, whoever caused it. This service keeps a per-player snapshot
--     of `profile.Stats`, `profile.Index` and `profile.Level`, diffs the new
--     profile against that snapshot on each change, and turns any positive
--     delta into quest progress. Zero coupling to Egg/CTF/etc.
--   - HatchRarity can't come from a stat counter (there's no
--     "EpicOrBetterHatched" counter), so it's derived from `profile.Index`
--     (brainrotId -> total ever hatched, maintained by DataService on every
--     grant): a positive delta on some id is looked up in a rarity table
--     built once from EggConfig.SpeciesByRarity.
--   - The snapshot is taken on `ProfileLoaded`, BEFORE any diffing happens,
--     so a player's entire pre-existing history never gets credited to a
--     freshly rolled quest set on join (the classic diff-tracker bug).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local QuestConfig = require(ReplicatedStorage.Shared.Quests.QuestConfig)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local QuestService = {}

local SECONDS_PER_DAY = 86400
local SECONDS_PER_WEEK = SECONDS_PER_DAY * 7
local DAILY_QUEST_COUNT = 3
local WEEKLY_QUEST_COUNT = 3

-- Maps a profile.Stats counter name to the quest Type it drives. Every entry
-- here is a 1:1, delta-based feed - the stat only ever counts up, so any
-- positive delta between snapshots is genuine new progress.
local STAT_TO_QUEST_TYPE: { [string]: QuestConfig.QuestType } = {
	EggsHatched = "HatchEggs",
	BrainrotsSold = "SellBrainrots",
	FlagCaptures = "CaptureFlags",
	FlagReturns = "ReturnFlags",
	Tags = "TagPlayers",
	RoundsWon = "WinRounds",
	RoundsPlayed = "PlayRounds",
	CoinsEarned = "EarnCoins",
}

-- brainrotId -> rarity, built once from the canonical Egg roster so
-- HatchRarity quests can look up "what rarity was this Index delta for"
-- without duplicating the roster here.
local rarityById: { [string]: string } = {}
for rarity, species in EggConfig.SpeciesByRarity do
	for _, brainrotId in species do
		rarityById[brainrotId] = rarity
	end
end

type Snapshot = {
	Stats: { [string]: number },
	Index: { [string]: number },
	Level: number,
}

local snapshots: { [Player]: Snapshot } = {}
local pushQueued: { [Player]: boolean } = {}

local questStateEvent: RemoteEvent
local claimResultEvent: RemoteEvent

local function utcDayIndex(t: number): number
	return math.floor(t / SECONDS_PER_DAY)
end

local function utcWeekIndex(t: number): number
	return math.floor(t / SECONDS_PER_WEEK)
end

local function takeSnapshot(profile: DataService.Profile): Snapshot
	local stats: { [string]: number } = {}
	for key, value in profile.Stats do
		stats[key] = value
	end
	local index: { [string]: number } = {}
	for key, value in profile.Index do
		index[key] = value
	end
	return { Stats = stats, Index = index, Level = profile.Level }
end

-- ReachLevel is "reach level N", not "gain N levels", so its initial
-- progress on roll must reflect the player's CURRENT level (a level-30
-- player handed a "reach level 10" quest should see it instantly
-- complete-but-unclaimed, not 0/10).
local function initialProgress(def: QuestConfig.QuestDefinition, profile: DataService.Profile): number
	if def.Type == "ReachLevel" then
		return math.min(def.Target, profile.Level)
	end
	return 0
end

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

-- Replaces every quest of the given tier in profile.Quests with a freshly
-- rolled set. Deterministic per (player, period-index) via the seed, per
-- QuestConfig.RollDailySet's contract.
local function refreshTier(player: Player, tier: QuestConfig.QuestTier)
	local now = os.time()

	if tier == "Daily" then
		local seed = player.UserId * 1000003 + utcDayIndex(now)
		local ids = QuestConfig.RollDailySet(seed, DAILY_QUEST_COUNT)
		DataService.Mutate(player, function(p)
			for id, _ in p.Quests do
				local def = QuestConfig.Pool[id]
				if def and def.Tier == "Daily" then
					p.Quests[id] = nil
				end
			end
			for _, id in ids do
				local def = QuestConfig.Pool[id]
				if def then
					p.Quests[id] = { Id = id, Progress = initialProgress(def, p), Claimed = false }
				end
			end
			p.QuestsRefreshedAt = now
		end)
	else
		local seed = player.UserId * 2000003 + utcWeekIndex(now)
		local ids = QuestConfig.RollWeeklySet(seed, WEEKLY_QUEST_COUNT)
		DataService.Mutate(player, function(p)
			for id, _ in p.Quests do
				local def = QuestConfig.Pool[id]
				if def and def.Tier == "Weekly" then
					p.Quests[id] = nil
				end
			end
			for _, id in ids do
				local def = QuestConfig.Pool[id]
				if def then
					p.Quests[id] = { Id = id, Progress = initialProgress(def, p), Claimed = false }
				end
			end
			-- profile.QuestsRefreshedAt is the only Quests-timing field
			-- reserved for us in DataService's Profile type. There's no
			-- second reserved field for the weekly cadence, so this stores
			-- an extra key directly on the profile table the same way
			-- ShopService stores ShopProcessedPurchaseIds: DataService's
			-- reconcile() only ever *adds* missing defaultProfile() keys
			-- into a loaded save, it never strips unknown ones, so this
			-- round-trips through save/load fine without needing a
			-- DataService edit.
			(p :: any).QuestsWeeklyRefreshedAt = now
		end)
	end
end

local function needsDailyRefresh(profile: DataService.Profile): boolean
	return utcDayIndex(os.time()) > utcDayIndex(profile.QuestsRefreshedAt)
end

local function needsWeeklyRefresh(profile: DataService.Profile): boolean
	local weeklyAt = (profile :: any).QuestsWeeklyRefreshedAt
	if type(weeklyAt) ~= "number" then
		weeklyAt = 0
	end
	return utcWeekIndex(os.time()) > utcWeekIndex(weeklyAt)
end

-- Detects a stale tier and re-rolls it exactly once, regardless of how many
-- days/weeks were skipped (e.g. a player offline for 9 days does NOT loop 9
-- times - "greater than" is a single boolean check either way). Returns true
-- if anything was refreshed.
local function checkRefresh(player: Player, profile: DataService.Profile): boolean
	local refreshed = false
	if needsDailyRefresh(profile) then
		refreshTier(player, "Daily")
		refreshed = true
	end
	if needsWeeklyRefresh(profile) then
		refreshTier(player, "Weekly")
		refreshed = true
	end
	return refreshed
end

local function pushState(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local daily = {}
	local weekly = {}
	for id, qp in profile.Quests do
		local def = QuestConfig.Pool[id]
		if def then
			local entry = {
				Id = id,
				Name = def.Name,
				Description = def.Description,
				Type = def.Type,
				Target = def.Target,
				Progress = qp.Progress,
				Claimed = qp.Claimed,
				Reward = def.Reward,
				Tier = def.Tier,
			}
			if def.Tier == "Daily" then
				table.insert(daily, entry)
			else
				table.insert(weekly, entry)
			end
		end
	end
	table.sort(daily, function(a, b)
		return a.Id < b.Id
	end)
	table.sort(weekly, function(a, b)
		return a.Id < b.Id
	end)

	local weeklyRefreshedAt = (profile :: any).QuestsWeeklyRefreshedAt
	if type(weeklyRefreshedAt) ~= "number" then
		weeklyRefreshedAt = 0
	end

	questStateEvent:FireClient(player, {
		Daily = daily,
		Weekly = weekly,
		NextDailyRefreshAt = (utcDayIndex(profile.QuestsRefreshedAt) + 1) * SECONDS_PER_DAY,
		NextWeeklyRefreshAt = (utcWeekIndex(weeklyRefreshedAt) + 1) * SECONDS_PER_WEEK,
		ServerTime = os.time(),
	})
end

-- Throttled push: a burst of ProfileChanged events (e.g. a x10 hatch) should
-- collapse into a single client push instead of ten, same pattern as
-- EconomyService.pushState.
local function queuePush(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			pushState(player)
		end
	end)
end

local function onProfileChanged(player: Player, profile: DataService.Profile)
	local snap = snapshots[player]
	if not snap then
		-- No snapshot yet (ProfileLoaded hasn't fired for this player through
		-- this service, or we missed it) - take one now rather than diff
		-- against nothing, which would otherwise look like infinite progress.
		snapshots[player] = takeSnapshot(profile)
		return
	end

	local statDeltas: { [string]: number } = {}
	for statName, questType in STAT_TO_QUEST_TYPE do
		local newValue = profile.Stats[statName] or 0
		local oldValue = snap.Stats[statName] or 0
		local delta = newValue - oldValue
		if delta > 0 then
			statDeltas[questType] = (statDeltas[questType] or 0) + delta
		end
	end

	local rarityDeltas: { [string]: number } = {}
	for brainrotId, newCount in profile.Index do
		local oldCount = snap.Index[brainrotId] or 0
		local delta = newCount - oldCount
		if delta > 0 then
			local rarity = rarityById[brainrotId]
			if rarity then
				rarityDeltas[rarity] = (rarityDeltas[rarity] or 0) + delta
			end
		end
	end

	local levelChanged = profile.Level ~= snap.Level
	local newLevel = profile.Level

	-- Update the snapshot now, using the (already mutated) profile, BEFORE
	-- any of our own DataService.Mutate calls below can trigger another
	-- (deferred) ProfileChanged re-entry. That re-entry will then diff
	-- against a snapshot that already reflects this event, computing zero
	-- delta and no-op'ing instead of double-counting or looping.
	snapshots[player] = takeSnapshot(profile)

	if next(statDeltas) == nil and next(rarityDeltas) == nil and not levelChanged then
		return
	end

	local completed: { string } = {}

	DataService.Mutate(player, function(p)
		for id, qp in p.Quests do
			if qp.Claimed then
				continue
			end
			local def = QuestConfig.Pool[id]
			if not def then
				continue
			end

			local before = qp.Progress
			local newProgress = before

			if def.Type == "ReachLevel" then
				if levelChanged then
					newProgress = math.min(def.Target, newLevel)
				end
			elseif def.Type == "HatchRarity" then
				local threshold = def.Rarity
				if threshold then
					local total = 0
					for rarity, amount in rarityDeltas do
						if QuestConfig.RarityMeetsOrExceeds(rarity, threshold) then
							total += amount
						end
					end
					if total > 0 then
						newProgress = math.min(def.Target, before + total)
					end
				end
			else
				local delta = statDeltas[def.Type]
				if delta and delta > 0 then
					newProgress = math.min(def.Target, before + delta)
				end
			end

			if newProgress ~= before then
				qp.Progress = newProgress
				if before < def.Target and newProgress >= def.Target then
					table.insert(completed, id)
				end
			end
		end
	end)

	for _, id in completed do
		local def = QuestConfig.Pool[id]
		if def then
			notify(player, `Quest complete: {def.Name}! Claim your reward.`, "Success")
		end
	end

	queuePush(player)
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	checkRefresh(player, profile)
	-- Snapshot AFTER the refresh (refreshing only touches Quests/timestamps,
	-- never Stats/Index/Level) and BEFORE anything else can diff against it -
	-- this is what stops a joining player's entire lifetime stat history from
	-- being credited to a brand new quest set.
	snapshots[player] = takeSnapshot(profile)
	pushState(player)
end

local function onPlayerRemoving(player: Player)
	snapshots[player] = nil
	pushQueued[player] = nil
end

local function onClaimReward(player: Player, questId: unknown)
	if typeof(questId) ~= "string" then
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		claimResultEvent:FireClient(player, { QuestId = questId, Success = false, Reason = "ProfileNotLoaded" })
		return
	end

	local def = QuestConfig.Pool[questId]
	local qp = profile.Quests[questId]
	if not def or not qp then
		claimResultEvent:FireClient(player, { QuestId = questId, Success = false, Reason = "NotFound" })
		return
	end
	if qp.Claimed then
		claimResultEvent:FireClient(player, { QuestId = questId, Success = false, Reason = "AlreadyClaimed" })
		return
	end
	-- Re-check completion server-side - never trust that the client only
	-- sends this once the bar is actually full.
	if qp.Progress < def.Target then
		claimResultEvent:FireClient(player, { QuestId = questId, Success = false, Reason = "Incomplete" })
		return
	end

	DataService.Mutate(player, function(p)
		local pq = p.Quests[questId]
		if pq then
			pq.Claimed = true
		end
	end)

	EconomyService.AwardBundle(player, def.Reward, `Quest: {def.Name}`)

	claimResultEvent:FireClient(player, { QuestId = questId, Success = true })
	pushState(player)
end

function QuestService.Init()
	questStateEvent = Net.GetEvent(Constants.REMOTE_NAMES.Quests.StateUpdated)
	claimResultEvent = Net.GetEvent(Constants.REMOTE_NAMES.Quests.ClaimResult)

	Net.GetEvent(Constants.REMOTE_NAMES.Quests.ClaimReward).OnServerEvent:Connect(onClaimReward)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
	DataService.ProfileChanged.Event:Connect(onProfileChanged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Defensive catch-up: a profile may have finished loading before this
	-- Init() ran (DataService loads players synchronously-ish during its own
	-- Init(), which runs earlier in Main.server.lua boot order), which would
	-- mean we missed that ProfileLoaded firing.
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end

	-- Catches the daily/weekly rollover for players who stay online across
	-- the boundary (ProfileLoaded/ProfileChanged alone wouldn't fire on their
	-- own just because a clock crossed midnight UTC).
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if profile and checkRefresh(player, profile) then
					queuePush(player)
				end
			end
		end
	end)
end

return QuestService
