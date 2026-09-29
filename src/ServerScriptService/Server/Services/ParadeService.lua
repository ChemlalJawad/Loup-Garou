--!strict
-- Server authority for the Brainrot Parade (red carpet).
--
-- Owns what walks and when, and validates every purchase: the walker must
-- still be on the carpet, unsold, within reach of the buyer (checked against
-- the same time-based position the clients render), and the buyer must have
-- the coins and a free slot. Clients only ever *ask* to buy a uid.
--
-- There is deliberately no stealing: in the genre's biggest game, losing a
-- Brainrot to another player is the most-documented source of upset young
-- players. Here the only competition is being first to buy - nobody can take
-- something you already own.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local Mutations = require(ReplicatedStorage.Shared.Brainrots.Mutations)
local ParadeConfig = require(ReplicatedStorage.Shared.Parade.ParadeConfig)
local LightingConfig = require(ReplicatedStorage.Shared.LightingConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)

local ParadeService = {}

type Walker = ParadeConfig.Walker

local rng = Random.new()
local walkers: { [string]: Walker } = {}
local activeCount = 0
local lastBuyAt: { [Player]: number } = {}

local spawnedEvent: RemoteEvent
local soldEvent: RemoteEvent
local stateEvent: RemoteEvent

-- AudioService is a sibling service; required defensively so the Parade
-- keeps working (silently) if audio is ever removed or fails to load.
local audioService: any = nil
do
	local moduleScript = script.Parent:FindFirstChild("AudioService")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			audioService = result
		end
	end
end

local function playFor(player: Player, cueId: string)
	if audioService and type(audioService.PlayFor) == "function" then
		pcall(audioService.PlayFor, player, cueId)
	end
end

local function playForAll(cueId: string)
	if audioService and type(audioService.PlayForAll) == "function" then
		pcall(audioService.PlayForAll, cueId)
	end
end

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function notifyAll(message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireAllClients(message, kind)
end

local function walkerDisplayName(walker: Walker): string
	return Mutations.DecorateName(EggConfig.DisplayName(walker.Id), walker.Mutation)
end

local function snapshot(): { Walker }
	local list = {}
	for _, walker in walkers do
		table.insert(list, walker)
	end
	return list
end

local function removeWalker(uid: string)
	if walkers[uid] then
		walkers[uid] = nil
		activeCount -= 1
	end
end

local function pruneExpired(now: number)
	for uid, walker in walkers do
		-- One second of grace past the end gate so a purchase that was
		-- in flight as the walker reached the end still resolves cleanly.
		if ParadeConfig.ProgressAt(walker, now) >= 1 + (1 / walker.Duration) then
			removeWalker(uid)
		end
	end
end

local function spawnWalker(now: number)
	local rarity = ParadeConfig.RollRarity(rng)
	local species = EggConfig.RollSpecies(rarity, rng)
	local chances = if LightingConfig.IsNight(now)
		then ParadeConfig.MutationChancesNight
		else ParadeConfig.MutationChancesDay
	local mutation = Mutations.Roll(chances, rng)

	local walker: Walker = {
		Uid = HttpService:GenerateGUID(false),
		Id = species,
		Rarity = rarity,
		Mutation = mutation,
		Price = ParadeConfig.PriceFor(rarity, mutation),
		SpawnedAt = now,
		Duration = ParadeConfig.WALK_SECONDS,
	}
	walkers[walker.Uid] = walker
	activeCount += 1
	spawnedEvent:FireAllClients(walker)

	local announceRarity = ParadeConfig.AnnounceRarities[rarity] == true
	local announceMutation = mutation ~= nil and ParadeConfig.AnnounceMutations[mutation] == true
	if announceRarity or announceMutation then
		notifyAll(
			`A {string.upper(rarity)} {walkerDisplayName(walker)} just stepped onto the Brainrot Parade! {ParadeConfig.FormatCoins(walker.Price)} Coins`,
			"Warning"
		)
		playForAll("ParadeHype")
	end
end

local function pushInventory(player: Player)
	local profile = DataService.Get(player)
	if profile then
		Net.GetEvent(Constants.REMOTE_NAMES.Egg.InventoryUpdated):FireClient(
			player,
			profile.OwnedBrainrots,
			profile.EquippedBrainrotUid
		)
	end
end

local function onBuy(player: Player, uid: unknown)
	if typeof(uid) ~= "string" then
		return
	end

	local now = workspace:GetServerTimeNow()
	local last = lastBuyAt[player]
	if last and now - last < ParadeConfig.BUY_COOLDOWN then
		return
	end
	lastBuyAt[player] = now

	local walker = walkers[uid]
	if not walker then
		notify(player, "Someone was faster - that Brainrot is already gone!", "Warning")
		return
	end

	if ParadeConfig.ProgressAt(walker, now) >= 1 then
		notify(player, "Too late - it already left the Parade.", "Warning")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local walkerPosition = ParadeConfig.PositionAt(walker, now)
	if (root.Position - walkerPosition).Magnitude > ParadeConfig.BUY_RADIUS then
		notify(player, "Get closer to the Brainrot to buy it!", "Info")
		return
	end

	if DataService.FreeSlots(player) < 1 then
		notify(player, "Your inventory is full - sell or merge some Brainrots first.", "Warning")
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if profile.Coins < walker.Price then
		local missing = walker.Price - profile.Coins
		notify(player, `You need {ParadeConfig.FormatCoins(missing)} more Coins for this one.`, "Warning")
		playFor(player, "PurchaseFail")
		return
	end

	-- Claim the walker before any mutation so a second request for the same
	-- uid (from anyone) can never also succeed.
	removeWalker(uid)

	if not DataService.TrySpendCoins(player, walker.Price) then
		-- Coins changed between the check and the spend; put it back.
		walkers[uid] = walker
		activeCount += 1
		return
	end

	local granted = DataService.AddBrainrot(player, walker.Id, walker.Rarity, walker.Mutation, "Parade")
	if not granted then
		-- Refund exactly what was spent (not an "earned" reward, so it must
		-- bypass EconomyService's multipliers).
		DataService.AddCoins(player, walker.Price)
		notify(player, "Purchase failed - your coins were refunded.", "Error")
		return
	end

	soldEvent:FireAllClients(uid, player.DisplayName)
	notify(player, `You got {walkerDisplayName(walker)}! Equip it from your Eggs inventory.`, "Success")
	playFor(player, "Purchase")
	pushInventory(player)
end

function ParadeService.Init()
	spawnedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Parade.Spawned)
	soldEvent = Net.GetEvent(Constants.REMOTE_NAMES.Parade.Sold)
	stateEvent = Net.GetEvent(Constants.REMOTE_NAMES.Parade.State)

	Net.GetEvent(Constants.REMOTE_NAMES.Parade.Buy).OnServerEvent:Connect(onBuy)
	-- Late joiners (and clients whose controller starts after a few spawns)
	-- ask for the current carpet instead of the server guessing when a
	-- client is ready to listen.
	Net.GetEvent(Constants.REMOTE_NAMES.Parade.RequestState).OnServerEvent:Connect(function(player)
		stateEvent:FireClient(player, snapshot())
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				local now = workspace:GetServerTimeNow()
				pruneExpired(now)
				if activeCount < ParadeConfig.MAX_ACTIVE then
					spawnWalker(now)
				end
			end)
			if not ok then
				warn("[ParadeService] tick errored:", err)
			end
			task.wait(ParadeConfig.SPAWN_INTERVAL)
		end
	end)
end

return ParadeService
