--!strict
-- Owns all player persistence. Every other service reads/writes player state
-- (coins, gems, inventory, equipped pet, gamepass cache, CTF stats) through
-- this module instead of touching DataStoreService directly.
--
-- Deliberately dependency-free (no ProfileService/Wally) so the project syncs
-- and runs from a bare Rojo checkout. Swap in ProfileService later if the
-- project grows session-locking needs beyond what ships here.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

export type OwnedBrainrot = {
	Uid: string,
	Id: string,
	Rarity: string,
	HatchedAt: number,
}

export type Profile = {
	Coins: number,
	Gems: number,
	OwnedBrainrots: { OwnedBrainrot },
	EquippedBrainrotUid: string?,
	InventorySlots: number,
	OwnedGamePasses: { [number]: boolean },
	Stats: {
		FlagCaptures: number,
		FlagReturns: number,
		Tags: number,
		EggsHatched: number,
	},
	Settings: {
		Music: boolean,
		SFX: boolean,
	},
}

local DATA_STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local MAX_RETRIES = 5
local RETRY_BASE_DELAY = 1.5

local function defaultProfile(): Profile
	return {
		Coins = Constants.STARTING_COINS,
		Gems = Constants.STARTING_GEMS,
		OwnedBrainrots = {},
		EquippedBrainrotUid = nil,
		InventorySlots = Constants.DEFAULT_INVENTORY_SLOTS,
		OwnedGamePasses = {},
		Stats = {
			FlagCaptures = 0,
			FlagReturns = 0,
			Tags = 0,
			EggsHatched = 0,
		},
		Settings = {
			Music = true,
			SFX = true,
		},
	}
end

-- Fills in any keys added to defaultProfile() after a player's save was
-- written, without clobbering their existing values.
local function reconcile(loaded: any): Profile
	local base = defaultProfile()
	if type(loaded) ~= "table" then
		return base
	end
	for key, value in pairs(base) do
		if loaded[key] == nil then
			loaded[key] = value
		elseif type(value) == "table" and type(loaded[key]) == "table" then
			for subKey, subValue in pairs(value) do
				if loaded[key][subKey] == nil then
					loaded[key][subKey] = subValue
				end
			end
		end
	end
	return loaded :: Profile
end

local DataService = {}

DataService.ProfileLoaded = Instance.new("BindableEvent")
DataService.ProfileChanged = Instance.new("BindableEvent") -- (player, profile) fired after any mutation

local profiles: { [Player]: Profile } = {}
local loadingComplete: { [Player]: boolean } = {}
local dataStoreAvailable = true

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)
	if ok then
		store = result
	else
		dataStoreAvailable = false
		warn("[DataService] DataStoreService unavailable, running in memory-only mode:", result)
	end
end

local function keyFor(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function attemptLoad(player: Player): Profile
	if not dataStoreAvailable or not store then
		return defaultProfile()
	end

	local key = keyFor(player)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return reconcile(result)
		end
		warn(string.format("[DataService] load attempt %d/%d failed for %s: %s", attempt, MAX_RETRIES, player.Name, tostring(result)))
		task.wait(RETRY_BASE_DELAY * attempt)
	end

	warn("[DataService] all load attempts failed for", player.Name, "- using defaults for this session")
	return defaultProfile()
end

local function attemptSave(player: Player, profile: Profile)
	if not dataStoreAvailable or not store then
		return
	end

	local key = keyFor(player)
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(key, profile)
		end)
		if ok then
			return
		end
		warn(string.format("[DataService] save attempt %d/%d failed for %s: %s", attempt, MAX_RETRIES, player.Name, tostring(err)))
		task.wait(RETRY_BASE_DELAY * attempt)
	end
	warn("[DataService] all save attempts failed for", player.Name, "- data for this session may be lost")
end

local function fireChanged(player: Player)
	local profile = profiles[player]
	if profile then
		DataService.ProfileChanged:Fire(player, profile)
	end
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.WaitForProfile(player: Player): Profile?
	if profiles[player] then
		return profiles[player]
	end
	local elapsed = 0
	while player.Parent and not profiles[player] and elapsed < 15 do
		task.wait(0.1)
		elapsed += 0.1
	end
	return profiles[player]
end

function DataService.AddCoins(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Coins = math.max(0, profile.Coins + amount)
	fireChanged(player)
end

function DataService.AddGems(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Gems = math.max(0, profile.Gems + amount)
	fireChanged(player)
end

function DataService.TrySpendCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	fireChanged(player)
	return true
end

function DataService.TrySpendGems(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Gems < amount then
		return false
	end
	profile.Gems -= amount
	fireChanged(player)
	return true
end

-- Returns the new OwnedBrainrot entry, or nil if the inventory is full.
function DataService.AddBrainrot(player: Player, id: string, rarity: string): DataService.OwnedBrainrot?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	if #profile.OwnedBrainrots >= profile.InventorySlots then
		return nil
	end

	local entry: DataService.OwnedBrainrot = {
		Uid = game:GetService("HttpService"):GenerateGUID(false),
		Id = id,
		Rarity = rarity,
		HatchedAt = os.time(),
	}
	table.insert(profile.OwnedBrainrots, entry)
	profile.Stats.EggsHatched += 1

	if not profile.EquippedBrainrotUid then
		profile.EquippedBrainrotUid = entry.Uid
	end

	fireChanged(player)
	return entry
end

function DataService.EquipBrainrot(player: Player, uid: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	for _, owned in profile.OwnedBrainrots do
		if owned.Uid == uid then
			profile.EquippedBrainrotUid = uid
			fireChanged(player)
			return true
		end
	end
	return false
end

function DataService.SetGamePassOwned(player: Player, passId: number, owned: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.OwnedGamePasses[passId] = owned or nil
	fireChanged(player)
end

function DataService.HasGamePass(player: Player, passId: number): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.OwnedGamePasses[passId] == true
end

function DataService.IncrementStat(player: Player, statName: string, amount: number?)
	local profile = profiles[player]
	if not profile or profile.Stats[statName] == nil then
		return
	end
	profile.Stats[statName] += (amount or 1)
	fireChanged(player)
end

local function onPlayerAdded(player: Player)
	loadingComplete[player] = false
	local profile = attemptLoad(player)
	if not player.Parent then
		-- Player left mid-load; discard.
		return
	end
	profiles[player] = profile
	loadingComplete[player] = true
	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		attemptSave(player, profile)
	end
	profiles[player] = nil
	loadingComplete[player] = nil
end

function DataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(attemptSave, player, profile)
			end
		end
	end)

	game:BindToClose(function()
		if not dataStoreAvailable then
			return
		end
		local remaining = 0
		for _ in profiles do
			remaining += 1
		end
		for player, profile in profiles do
			attemptSave(player, profile)
			remaining -= 1
		end
	end)
end

return DataService
