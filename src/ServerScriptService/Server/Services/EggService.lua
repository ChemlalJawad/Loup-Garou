--!strict
-- Server-authoritative egg hatching. Validates requests, spends currency,
-- rolls rarity/species from EggConfig, grants brainrots via DataService, and
-- pushes results back to the requesting client. Never trusts a client-sent
-- rarity, species, or cost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)

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

	local profile = DataService.Get(player)
	if not profile then
		return
	end

	-- Check inventory room BEFORE spending any currency.
	local freeSlots = profile.InventorySlots - #profile.OwnedBrainrots
	if freeSlots < hatchCount then
		notify(player, "Inventory full - sell or use more slots!", "Warning")
		fireHatchResult(player, { Success = false, Reason = "InventoryFull" })
		return
	end

	local totalCost = egg.Cost * hatchCount
	local spent: boolean
	if egg.Currency == Constants.CURRENCY.HARD then
		spent = DataService.TrySpendGems(player, totalCost)
	else
		spent = DataService.TrySpendCoins(player, totalCost)
	end

	if not spent then
		notify(player, `Not enough {egg.Currency}!`, "Error")
		fireHatchResult(player, { Success = false, Reason = "NotEnoughCurrency" })
		return
	end

	local luckBoosted = DataService.GetPerk(player, "DoubleLuck")
	local results: { HatchResultEntry } = {}

	for _ = 1, hatchCount do
		local species, rarity = EggConfig.RollOne(egg.Id, luckBoosted, rng)
		local owned = DataService.AddBrainrot(player, species, rarity)
		if owned then
			table.insert(results, { Id = owned.Id, Rarity = owned.Rarity, Uid = owned.Uid })
		end
	end

	fireHatchResult(player, { Success = true, EggId = egg.Id, Results = results })
	pushInventory(player, profile)
end

local function onEquipPet(player: Player, uid: unknown)
	if typeof(uid) ~= "string" then
		return
	end

	local ok = DataService.EquipBrainrot(player, uid)
	if not ok then
		return
	end

	local profile = DataService.Get(player)
	if profile then
		pushInventory(player, profile)
	end
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	pushInventory(player, profile)
end

function EggService.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.RequestHatch).OnServerEvent:Connect(onRequestHatch)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.EquipPet).OnServerEvent:Connect(onEquipPet)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
end

return EggService
