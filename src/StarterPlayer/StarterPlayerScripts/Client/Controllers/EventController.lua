--!strict
-- Client side of world events (Coin Rain).
--
-- The server sends the coin list once; this controller drops the coins from
-- the sky in a staggered shower, spins them, and detects pickups locally so
-- a coin vanishes the instant you touch it. The pickup is then confirmed by
-- the server (EventService), which is the only place coins are awarded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EventConfig = require(ReplicatedStorage.Shared.Events.EventConfig)
local FX = require(ReplicatedStorage.Shared.Effects.FX)

local EventController = {}

type CoinVisual = {
	Id: number,
	Target: Vector3,
	Part: BasePart,
	DropAt: number, -- os.clock() when this coin starts falling
}

type ActiveRain = {
	EventId: string,
	EndsAt: number,
	Coins: { [number]: CoinVisual },
	Folder: Folder,
}

local COIN_COLOR = Color3.fromRGB(255, 200, 60)
local DROP_HEIGHT = 45
local FALL_SECONDS = 1.1
local STAGGER_SECONDS = 2.5
local PICKUP_CHECK_INTERVAL = 1 / 15
local NEAR_ZONE_DISTANCE = 260

local localPlayer = Players.LocalPlayer
local active: ActiveRain? = nil
local zoneCenter = WorldLayout.Get(EventConfig.COIN_RAIN.Zone).Center

local function clearRain()
	local rain = active
	if rain then
		rain.Folder:Destroy()
		active = nil
	end
end

local function removeCoin(coinId: number, burst: boolean)
	local rain = active
	if not rain then
		return
	end
	local coin = rain.Coins[coinId]
	if not coin then
		return
	end
	rain.Coins[coinId] = nil
	if burst then
		FX.Burst(coin.Part.Position, COIN_COLOR, 8)
	end
	coin.Part:Destroy()
end

local function onStarted(payload: EventConfig.CoinRainPayload)
	clearRain()

	local folder = Instance.new("Folder")
	folder.Name = "CoinRain"
	folder.Parent = Workspace

	local now = os.clock()
	local coins: { [number]: CoinVisual } = {}
	for _, coin in payload.Coins do
		local part = Instance.new("Part")
		part.Name = "Coin"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.4, 2.4, 2.4)
		part.Color = COIN_COLOR
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1 -- hidden until its turn to fall
		part.CFrame = CFrame.new(coin.Position + Vector3.new(0, DROP_HEIGHT, 0))
		part.Parent = folder

		coins[coin.Id] = {
			Id = coin.Id,
			Target = coin.Position,
			Part = part,
			DropAt = now + math.random() * STAGGER_SECONDS,
		}
	end

	active = {
		EventId = payload.EventId,
		EndsAt = payload.EndsAt,
		Coins = coins,
		Folder = folder,
	}
end

local function localRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function EventController.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Event.Started).OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Kind == "CoinRain" then
			onStarted(payload :: EventConfig.CoinRainPayload)
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Event.CoinCollected).OnClientEvent:Connect(function(eventId, coinId)
		local rain = active
		if rain and eventId == rain.EventId and type(coinId) == "number" then
			removeCoin(coinId, true)
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Event.Ended).OnClientEvent:Connect(function(eventId)
		local rain = active
		if rain and eventId == rain.EventId then
			clearRain()
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Event.RequestState):FireServer()

	local sincePickupCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		local rain = active
		if not rain then
			return
		end
		-- Safety net if the Ended message is ever missed.
		if workspace:GetServerTimeNow() > rain.EndsAt + 3 then
			clearRain()
			return
		end

		local root = localRoot()
		if not root or (root.Position - zoneCenter).Magnitude > NEAR_ZONE_DISTANCE then
			return -- nobody can see or reach the coins from here
		end

		local now = os.clock()
		local spin = now * 4
		sincePickupCheck += dt
		local checkPickups = sincePickupCheck >= PICKUP_CHECK_INTERVAL
		if checkPickups then
			sincePickupCheck = 0
		end

		for coinId, coin in rain.Coins do
			local fallProgress = (now - coin.DropAt) / FALL_SECONDS
			if fallProgress >= 0 then
				local t = math.min(fallProgress, 1)
				local height = DROP_HEIGHT * (1 - t * t) -- accelerate like it's falling
				coin.Part.Transparency = 0
				coin.Part.CFrame = CFrame.new(coin.Target + Vector3.new(0, height, 0)) * CFrame.Angles(0, spin + coinId, 0)

				if
					checkPickups
					and t >= 1
					and (root.Position - coin.Target).Magnitude <= EventConfig.COIN_RAIN.ClientPickupRadius
				then
					-- Vanish immediately for responsiveness; the server
					-- decides whether it actually counts.
					removeCoin(coinId, true)
					Net.GetEvent(Constants.REMOTE_NAMES.Event.Collect):FireServer(rain.EventId, coinId)
				end
			end
		end
	end)
end

return EventController
