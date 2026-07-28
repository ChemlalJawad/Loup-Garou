--!strict
-- Server-authoritative egg hatching, collection management, and auto-hatch.
-- Validates requests, spends currency, rolls rarity/species from EggConfig,
-- grants brainrots via DataService, and pushes results back to the requesting
-- client. Never trusts a client-sent rarity, species, uid, or cost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

export type HatchResultEntry = {
	Id: string,
	Rarity: string,
	Uid: string,
}

export type HatchResultPayload = {
	Success: boolean,
	EggId: string?,
	Results: { HatchResultEntry }?,
	Reason: ("NotEnoughCurrency" | "InventoryFull" | "InvalidRequest")?,
}

local EggService = {}

local rng = Random.new()

-- How often an auto-hatch loop attempts another hatch for a player. Sits in
-- the "quality of life, not idle-forever AFK farm" range this genre uses.
local AUTO_HATCH_INTERVAL_SECONDS = 2

-- Selling duplicates in bulk defaults to this rarity ceiling (inclusive) when
-- the client doesn't explicitly ask for a higher one, so a fat-fingered click
-- can never mass-sell Epics/Legendaries/Secrets by accident.
local DEFAULT_SELL_DUPLICATES_MAX_RARITY = "Rare"

-- Pity counters: see the long comment in EggConfig.lua next to
-- EggConfig.PityThreshold for why this lives in memory instead of the
-- profile. Keyed by Player and by egg id, since each egg tracks its own pity.
local pityCounters: { [Player]: { [string]: number } } = {}

-- Auto-hatch: `active` state per player (what SHOULD be happening, persisted
-- to profile.AutoHatch) plus a `running` flag so SetAutoHatch toggling on/off
-- rapidly never spawns a second loop thread for the same player.
type AutoHatchState = {
	Active: boolean,
	EggId: string,
}
local autoHatchState: { [Player]: AutoHatchState } = {}
local autoHatchRunning: { [Player]: boolean } = {}

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function fireHatchResult(player: Player, payload: HatchResultPayload)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.HatchResult):FireClient(player, payload)
end

local function pushInventory(player: Player, profile: DataService.Profile)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.InventoryUpdated):FireClient(
		player,
		profile.OwnedBrainrots,
		profile.EquippedBrainrotUid
	)
end

local function pushInventoryFor(player: Player)
	local profile = DataService.Get(player)
	if profile then
		pushInventory(player, profile)
	end
end

local epicIndex = EggConfig.RarityIndex(EggConfig.PityFloorRarity) or 3

-- Rolls one species+rarity for `eggId`, applying that player's pity counter
-- for that specific egg. Resets the counter to 0 on an Epic-or-better result,
-- otherwise increments it. Returns (species, rarity).
local function rollWithPity(player: Player, eggId: string, luckBoosted: boolean): (string, string)
	local perPlayer = pityCounters[player]
	if not perPlayer then
		perPlayer = {}
		pityCounters[player] = perPlayer
	end

	local pityCount = perPlayer[eggId] or 0
	local threshold = EggConfig.PityThreshold[eggId]
	local forcePity = threshold ~= nil and pityCount + 1 >= threshold

	local rarity: string
	if forcePity then
		rarity = EggConfig.RollRarityForced(eggId, EggConfig.PityFloorRarity, rng)
	else
		rarity = EggConfig.RollRarity(eggId, luckBoosted, rng)
	end

	local rarityIndex = EggConfig.RarityIndex(rarity) or 1
	perPlayer[eggId] = if rarityIndex >= epicIndex then 0 else pityCount + 1

	local species = EggConfig.RollSpecies(rarity, rng)
	return species, rarity
end

-- Core hatch flow shared by manual hatch requests and auto-hatch ticks.
-- Validates slots/currency, spends, rolls (with pity), grants. Never fires
-- remotes itself so callers can decide what feedback to send.
local function tryHatch(player: Player, eggId: string, hatchCount: number): (boolean, string?, { HatchResultEntry }?)
	local egg = EggConfig.GetEgg(eggId)
	if not egg then
		return false, "InvalidRequest", nil
	end

	local profile = DataService.Get(player)
	if not profile then
		return false, "InvalidRequest", nil
	end

	-- Check inventory room BEFORE spending any currency.
	if DataService.FreeSlots(player) < hatchCount then
		return false, "InventoryFull", nil
	end

	local totalCost = egg.Cost * hatchCount
	local spent: boolean
	if egg.Currency == Constants.CURRENCY.HARD then
		spent = DataService.TrySpendGems(player, totalCost)
	else
		spent = DataService.TrySpendCoins(player, totalCost)
	end

	if not spent then
		return false, "NotEnoughCurrency", nil
	end

	local luckBoosted = EconomyService.HasLuckBoost(player)
	local results: { HatchResultEntry } = {}

	for _ = 1, hatchCount do
		local species, rarity = rollWithPity(player, egg.Id, luckBoosted)
		local owned = DataService.AddBrainrot(player, species, rarity)
		if owned then
			table.insert(results, { Id = owned.Id, Rarity = owned.Rarity, Uid = owned.Uid })
		end
	end

	return true, nil, results
end

-- Auto-hatch -----------------------------------------------------------------

local function stopAutoHatch(player: Player, reasonMessage: string?)
	local state = autoHatchState[player]
	if state then
		state.Active = false
	end
	autoHatchState[player] = nil

	DataService.Mutate(player, function(profile)
		profile.AutoHatch.Enabled = false
	end)

	if reasonMessage then
		notify(player, reasonMessage, "Warning")
	end
end

-- One auto-hatch attempt. Returns false (and stops the loop) the moment the
-- player can no longer afford it or has no room, rather than silently
-- retrying forever.
local function autoHatchTick(player: Player, eggId: string): boolean
	local egg = EggConfig.GetEgg(eggId)
	if not egg then
		stopAutoHatch(player, "Auto-hatch stopped: invalid egg.")
		return false
	end

	local ok, reason, results = tryHatch(player, eggId, 1)
	if not ok then
		if reason == "InventoryFull" then
			stopAutoHatch(player, "Auto-hatch stopped: inventory is full.")
		elseif reason == "NotEnoughCurrency" then
			stopAutoHatch(player, `Auto-hatch stopped: not enough {egg.Currency}.`)
		else
			stopAutoHatch(player, "Auto-hatch stopped.")
		end
		return false
	end

	fireHatchResult(player, { Success = true, EggId = egg.Id, Results = results })
	pushInventoryFor(player)
	return true
end

-- Spawns the loop thread for a player if one isn't already running. Safe to
-- call repeatedly (e.g. from SetAutoHatch and from ProfileLoaded on rejoin)
-- since `autoHatchRunning` guards against a second thread ever starting.
local function startAutoHatchLoop(player: Player)
	if autoHatchRunning[player] then
		return
	end
	autoHatchRunning[player] = true

	task.spawn(function()
		while true do
			local state = autoHatchState[player]
			if not state or not state.Active or not player.Parent then
				break
			end

			task.wait(AUTO_HATCH_INTERVAL_SECONDS)

			state = autoHatchState[player]
			if not state or not state.Active or not player.Parent then
				break
			end

			if not autoHatchTick(player, state.EggId) then
				break
			end
		end
		autoHatchRunning[player] = nil
	end)
end

-- Remote handlers -------------------------------------------------------------

local function onRequestHatch(player: Player, eggId: unknown, hatchCount: unknown)
	if typeof(eggId) ~= "string" or typeof(hatchCount) ~= "number" then
		return
	end

	local egg = EggConfig.GetEgg(eggId)
	if not egg then
		return
	end

	if not table.find(EggConfig.HatchCounts, hatchCount) then
		return
	end

	local ok, reason, results = tryHatch(player, eggId, hatchCount)
	if not ok then
		if reason == "InventoryFull" then
			notify(player, "Inventory full - sell or merge duplicates!", "Warning")
		elseif reason == "NotEnoughCurrency" then
			notify(player, `Not enough {egg.Currency}!`, "Error")
		end
		fireHatchResult(player, { Success = false, Reason = reason })
		return
	end

	fireHatchResult(player, { Success = true, EggId = egg.Id, Results = results })
	pushInventoryFor(player)
end

local function onEquipPet(player: Player, uid: unknown)
	if typeof(uid) ~= "string" then
		return
	end

	local ok = DataService.EquipBrainrot(player, uid)
	if not ok then
		return
	end

	pushInventoryFor(player)
end

local function onSellBrainrot(player: Player, uid: unknown)
	if typeof(uid) ~= "string" then
		return
	end

	local owned = DataService.FindBrainrot(player, uid)
	if not owned then
		return
	end

	-- Deliberately refuse rather than auto-unequip: silently swapping a
	-- player's active Brainrot out from under them (mid CTF match, no less)
	-- is worse than making them equip something else first.
	local equipped = DataService.GetEquipped(player)
	if equipped and equipped.Uid == uid then
		notify(player, "Unequip that Brainrot before selling it.", "Warning")
		return
	end

	local removed = DataService.RemoveBrainrot(player, uid)
	if not removed then
		return
	end

	local refund = Constants.SELL_VALUE[removed.Rarity] or 0
	EconomyService.AwardCoins(player, refund, `Sold {EggConfig.DisplayName(removed.Id)}`)
	DataService.IncrementStat(player, "BrainrotsSold", 1)
	pushInventoryFor(player)
end

local function onSellDuplicates(player: Player, options: unknown)
	local maxRarity = DEFAULT_SELL_DUPLICATES_MAX_RARITY
	if typeof(options) == "table" then
		local requested = (options :: any).MaxRarity
		if typeof(requested) == "string" and table.find(Constants.RARITY_ORDER, requested) then
			maxRarity = requested
		end
	end
	local maxIndex = EggConfig.RarityIndex(maxRarity) or (EggConfig.RarityIndex(DEFAULT_SELL_DUPLICATES_MAX_RARITY) :: number)

	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local equippedUid = profile.EquippedBrainrotUid

	-- Decide, per species, which single uid survives the cull: the equipped
	-- one if it's of that species, otherwise the first one encountered. Every
	-- other owned entry of that species is a "duplicate" and eligible to sell
	-- (subject to the rarity cap).
	local keepUidBySpecies: { [string]: string } = {}
	for _, owned in profile.OwnedBrainrots do
		if owned.Uid == equippedUid then
			keepUidBySpecies[owned.Id] = owned.Uid
		end
	end
	for _, owned in profile.OwnedBrainrots do
		if not keepUidBySpecies[owned.Id] then
			keepUidBySpecies[owned.Id] = owned.Uid
		end
	end

	local uidsToSell: { string } = {}
	local totalRefund = 0
	for _, owned in profile.OwnedBrainrots do
		local rarityIndex = EggConfig.RarityIndex(owned.Rarity) or 1
		if owned.Uid ~= keepUidBySpecies[owned.Id] and owned.Uid ~= equippedUid and rarityIndex <= maxIndex then
			table.insert(uidsToSell, owned.Uid)
			totalRefund += Constants.SELL_VALUE[owned.Rarity] or 0
		end
	end

	if #uidsToSell == 0 then
		notify(player, "No eligible duplicates to sell.", "Info")
		return
	end

	for _, uid in uidsToSell do
		DataService.RemoveBrainrot(player, uid)
	end
	DataService.IncrementStat(player, "BrainrotsSold", #uidsToSell)
	EconomyService.AwardCoins(player, totalRefund, `Sold {#uidsToSell} duplicates`)
	notify(player, `Sold {#uidsToSell} duplicates for {totalRefund} Coins.`, "Success")

	pushInventoryFor(player)
end

local function onMergeBrainrots(player: Player, brainrotId: unknown)
	if typeof(brainrotId) ~= "string" then
		return
	end

	local rarity = EggConfig.RarityOf(brainrotId)
	if not rarity then
		return
	end

	local nextRarity = EggConfig.NextRarity(rarity)
	if not nextRarity then
		notify(player, `{EggConfig.DisplayName(brainrotId)} is already the top rarity tier.`, "Warning")
		return
	end

	local owned = DataService.CountBrainrotsOfId(player, brainrotId)
	if owned < Constants.MERGE_COST then
		notify(player, `Need {Constants.MERGE_COST}x {EggConfig.DisplayName(brainrotId)} to merge.`, "Warning")
		return
	end

	if DataService.FreeSlots(player) < 1 then
		notify(player, "No free inventory slot for the merged Brainrot.", "Warning")
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		return
	end

	-- Prefer consuming non-equipped duplicates first, so merging never eats
	-- the player's currently-equipped Brainrot unless it's unavoidable (they
	-- own exactly MERGE_COST and one of them happens to be equipped).
	local equippedUid = profile.EquippedBrainrotUid
	local uidsToRemove: { string } = {}
	for _, entry in profile.OwnedBrainrots do
		if entry.Id == brainrotId and entry.Uid ~= equippedUid and #uidsToRemove < Constants.MERGE_COST then
			table.insert(uidsToRemove, entry.Uid)
		end
	end
	if #uidsToRemove < Constants.MERGE_COST then
		for _, entry in profile.OwnedBrainrots do
			if entry.Id == brainrotId and entry.Uid == equippedUid and #uidsToRemove < Constants.MERGE_COST then
				table.insert(uidsToRemove, entry.Uid)
			end
		end
	end

	if #uidsToRemove < Constants.MERGE_COST then
		-- Shouldn't happen given the count check above, but never consume a
		-- partial set.
		return
	end

	for _, uid in uidsToRemove do
		DataService.RemoveBrainrot(player, uid)
	end

	local newSpecies = EggConfig.RollSpecies(nextRarity, rng)
	local granted = DataService.AddBrainrot(player, newSpecies, nextRarity)
	if not granted then
		-- Extremely unlikely race (slots filled between the check above and
		-- this mutation). The duplicates are already spent; tell the player
		-- plainly rather than silently eating them.
		notify(player, "Merge failed - inventory became full mid-merge.", "Error")
		pushInventoryFor(player)
		return
	end

	notify(player, `Merged into {EggConfig.DisplayName(newSpecies)} ({nextRarity})!`, "Success")
	pushInventoryFor(player)
end

local function onSetAutoHatch(player: Player, enabled: unknown, eggId: unknown)
	if typeof(enabled) ~= "boolean" then
		return
	end

	if not enabled then
		stopAutoHatch(player, nil)
		return
	end

	if typeof(eggId) ~= "string" then
		return
	end
	local egg = EggConfig.GetEgg(eggId)
	if not egg then
		return
	end

	autoHatchState[player] = { Active = true, EggId = eggId }
	DataService.Mutate(player, function(profile)
		profile.AutoHatch.Enabled = true
		profile.AutoHatch.EggId = eggId
	end)
	notify(player, `Auto-hatch enabled: {egg.Name}.`, "Success")
	startAutoHatchLoop(player)
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	pushInventory(player, profile)

	local autoHatch = profile.AutoHatch
	if autoHatch.Enabled and autoHatch.EggId and EggConfig.GetEgg(autoHatch.EggId) then
		autoHatchState[player] = { Active = true, EggId = autoHatch.EggId }
		startAutoHatchLoop(player)
	end
end

local function onPlayerRemoving(player: Player)
	local state = autoHatchState[player]
	if state then
		state.Active = false
	end
	autoHatchState[player] = nil
	autoHatchRunning[player] = nil
	pityCounters[player] = nil
end

function EggService.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.RequestHatch).OnServerEvent:Connect(onRequestHatch)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.EquipPet).OnServerEvent:Connect(onEquipPet)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SellBrainrot).OnServerEvent:Connect(onSellBrainrot)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SellDuplicates).OnServerEvent:Connect(onSellDuplicates)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.MergeBrainrots).OnServerEvent:Connect(onMergeBrainrots)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SetAutoHatch).OnServerEvent:Connect(onSetAutoHatch)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return EggService
