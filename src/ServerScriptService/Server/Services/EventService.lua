--!strict
-- Runs scheduled world events. Lucky Rainbow: sets a Workspace attribute
-- (see EventConfig.LUCKY_RAINBOW) that ParadeService reads. Coin Rain: the server picks coin positions,
-- tells every client (who render and animate the coins locally), and
-- validates each pickup - the coin must exist, be unclaimed, and be near the
-- player who claims it. First come, first served, one coin one winner.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EventConfig = require(ReplicatedStorage.Shared.Events.EventConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)
local AudioService = require(ServerScriptService.Server.Services.AudioService)

local EventService = {}

type ActiveRain = {
	Payload: EventConfig.CoinRainPayload,
	Remaining: { [number]: Vector3 }, -- coinId -> position, removed on pickup
	Grabbed: { [Player]: number }, -- coins earned per player, for the end summary
}

local rng = Random.new()
local active: ActiveRain? = nil
local pickupTimes: { [Player]: { number } } = {}

local startedEvent: RemoteEvent
local endedEvent: RemoteEvent
local collectedEvent: RemoteEvent

local function notifyAll(message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireAllClients(message, kind)
end

local function generateCoins(): { EventConfig.Coin }
	local config = EventConfig.COIN_RAIN
	local zone = WorldLayout.Get(config.Zone)
	local halfX = zone.Size.X / 2 - config.EdgeMargin
	local halfZ = zone.Size.Z / 2 - config.EdgeMargin
	local coins = {}
	local attempts = 0
	while #coins < config.CoinCount and attempts < config.CoinCount * 10 do
		attempts += 1
		local offset = Vector3.new(rng:NextNumber(-halfX, halfX), 0, rng:NextNumber(-halfZ, halfZ))
		if offset.Magnitude >= config.AvoidCenterRadius then
			table.insert(coins, {
				Id = #coins + 1,
				-- zone.Center already sits at WorldLayout.GroundY.
				Position = zone.Center + offset + Vector3.new(0, config.HoverHeight, 0),
			})
		end
	end
	return coins
end

-- Sliding one-second window per player.
local function withinRateLimit(player: Player, now: number): boolean
	local times = pickupTimes[player]
	if not times then
		times = {}
		pickupTimes[player] = times
	end
	local list = times :: { number }
	while #list > 0 and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= EventConfig.COIN_RAIN.MaxPickupsPerSecond then
		return false
	end
	table.insert(list, now)
	return true
end

local function onCollect(player: Player, eventId: unknown, coinId: unknown)
	local rain = active
	if not rain or typeof(eventId) ~= "string" or typeof(coinId) ~= "number" then
		return
	end
	if eventId ~= rain.Payload.EventId then
		return
	end
	local position = rain.Remaining[coinId]
	if not position then
		return -- already taken (or never existed)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - position).Magnitude > EventConfig.COIN_RAIN.ServerPickupRadius then
		return
	end
	if not withinRateLimit(player, os.clock()) then
		return
	end

	rain.Remaining[coinId] = nil
	collectedEvent:FireAllClients(eventId, coinId)

	local profile = DataService.Get(player)
	local level = if profile then profile.Level else 1
	local value = EventConfig.COIN_RAIN.BaseValue + level * EventConfig.COIN_RAIN.PerLevel
	local granted = EconomyService.AwardCoins(player, value, "Coin Rain")
	rain.Grabbed[player] = (rain.Grabbed[player] or 0) + granted
end

local function runCoinRain()
	local config = EventConfig.COIN_RAIN
	notifyAll(`Coin Rain in the Central Plaza in {config.Warning} seconds - run!`, "Warning")
	task.wait(config.Warning)

	local coins = generateCoins()
	local remaining: { [number]: Vector3 } = {}
	for _, coin in coins do
		remaining[coin.Id] = coin.Position
	end
	local payload: EventConfig.CoinRainPayload = {
		EventId = HttpService:GenerateGUID(false),
		Kind = "CoinRain",
		EndsAt = workspace:GetServerTimeNow() + config.Duration,
		Coins = coins,
	}
	local rain: ActiveRain = { Payload = payload, Remaining = remaining, Grabbed = {} }
	active = rain
	startedEvent:FireAllClients(payload)
	AudioService.PlayForAll("CoinRainStart")

	task.wait(config.Duration)

	active = nil
	endedEvent:FireAllClients(payload.EventId)
	for player, total in rain.Grabbed do
		if player.Parent then
			Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(
				player,
				`Coin Rain over - you grabbed {total} Coins!`,
				"Success"
			)
		end
	end
end

local function runLuckyRainbow()
	local config = EventConfig.LUCKY_RAINBOW
	workspace:SetAttribute(config.Attribute, workspace:GetServerTimeNow() + config.Duration)
	notifyAll("A Lucky Rainbow is out! Parade Brainrots are twice as likely to be mutated.", "Success")
	AudioService.PlayForAll("LuckyRainbowStart")
	task.wait(config.Duration)
	-- The attribute's end time already expires it for every reader; clearing
	-- it just keeps the Workspace tidy.
	workspace:SetAttribute(config.Attribute, nil)
	notifyAll("The rainbow fades... see you next time!", "Info")
end

function EventService.Init()
	startedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Event.Started)
	endedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Event.Ended)
	collectedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Event.CoinCollected)

	Net.GetEvent(Constants.REMOTE_NAMES.Event.Collect).OnServerEvent:Connect(onCollect)

	-- Late joiners mid-rain get the coins that are still up for grabs.
	Net.GetEvent(Constants.REMOTE_NAMES.Event.RequestState).OnServerEvent:Connect(function(player)
		local rain = active
		if not rain then
			return
		end
		local stillThere = {}
		for coinId, position in rain.Remaining do
			table.insert(stillThere, { Id = coinId, Position = position })
		end
		startedEvent:FireClient(player, {
			EventId = rain.Payload.EventId,
			Kind = rain.Payload.Kind,
			EndsAt = rain.Payload.EndsAt,
			Coins = stillThere,
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		pickupTimes[player] = nil
	end)

	task.spawn(function()
		task.wait(EventConfig.COIN_RAIN.FirstDelay)
		while true do
			local ok, err = pcall(runCoinRain)
			if not ok then
				warn("[EventService] coin rain errored:", err)
				active = nil
			end
			task.wait(EventConfig.COIN_RAIN.Interval)
		end
	end)

	task.spawn(function()
		task.wait(EventConfig.LUCKY_RAINBOW.FirstDelay)
		while true do
			local ok, err = pcall(runLuckyRainbow)
			if not ok then
				warn("[EventService] lucky rainbow errored:", err)
				workspace:SetAttribute(EventConfig.LUCKY_RAINBOW.Attribute, nil)
			end
			task.wait(EventConfig.LUCKY_RAINBOW.Interval)
		end
	end)
end

return EventService
