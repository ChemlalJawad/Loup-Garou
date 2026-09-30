--!strict
-- The welcome committee: three Brainrots standing around the Hub spawn pad,
-- bobbing, turning to face you, and chatting in speech bubbles ("Welcome!",
-- "Let's hatch eggs!"). Walk up and tap "Say hi" - they hop and throw
-- hearts. Pure decoration, no reward, so there's nothing to farm.
--
-- Client-only like AmbientLifeController: local models, zero network
-- traffic, animated only while you're close. If uploaded art for a species
-- arrives later (ModelAssetService), the greeter rebuilds with it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local BrainrotModels = require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
local FX = require(ReplicatedStorage.Shared.Effects.FX)

local GreeterController = {}

-- Around the spawn pad (HubZone: pad centre = Hub centre + (0, 2, 17.5),
-- dais top at GroundY + 2). Kept clear of the pad, the fountain basin and
-- the map board.
local DAIS_Y = WorldLayout.GroundY + 2
local GREETERS = {
	{ Species = "PinguinoMandolino", Rarity = "Common", Offset = Vector3.new(-11, 0, 10) },
	{ Species = "TungTungTamburo", Rarity = "Epic", Offset = Vector3.new(-12, 0, 20) },
	{ Species = "CannoliniVolpe", Rarity = "Common", Offset = Vector3.new(10, 0, 8.5) },
}
local LINES = {
	"Welcome!",
	"Hi there!",
	"Let's hatch eggs!",
	"Check the map board!",
	"Follow the glowing trail!",
	"Tap me to say hi!",
	"Coin Rain soon?",
	"Visit the Parade!",
}
local ANIMATE_DISTANCE = 140
local TURN_DISTANCE = 30
local HEART_COLOR = Color3.fromRGB(255, 110, 160)

type Greeter = {
	Species: string,
	Rarity: string,
	Home: Vector3,
	Model: Model?,
	BuildPivot: CFrame,
	Bubble: TextLabel?,
	Facing: Vector3,
	HopUntil: number,
	NextLineAt: number,
	Phase: number,
}

local localPlayer = Players.LocalPlayer
local rng = Random.new()
local greeters: { Greeter } = {}
local folder: Folder

local function say(greeter: Greeter, text: string)
	local bubble = greeter.Bubble
	if bubble then
		bubble.Text = text
	end
end

local function build(greeter: Greeter)
	local ok, result = pcall(BrainrotModels.BuildStatic, greeter.Species, greeter.Rarity :: any)
	if not ok or typeof(result) ~= "Instance" then
		return
	end
	local model = result :: Model
	if greeter.Model then
		greeter.Model:Destroy()
	end
	greeter.Model = model
	greeter.BuildPivot = model:GetPivot()

	local primary = model.PrimaryPart
	if primary then
		-- Speech bubble.
		local gui = Instance.new("BillboardGui")
		gui.Name = "SpeechBubble"
		gui.Size = UDim2.new(0, 170, 0, 44)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		gui.MaxDistance = 60
		gui.LightInfluence = 0
		gui.Parent = primary
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		label.TextColor3 = Color3.fromRGB(50, 40, 60)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = LINES[1]
		label.Parent = gui
		Instance.new("UICorner").Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = label
		greeter.Bubble = label

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Say hi"
		prompt.ObjectText = EggConfig.DisplayName(greeter.Species)
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = primary
		prompt.Triggered:Connect(function()
			greeter.HopUntil = os.clock() + 0.45
			say(greeter, "Hi friend! <3")
			greeter.NextLineAt = os.clock() + 3
			FX.Burst(greeter.Home + Vector3.new(0, 3, 0), HEART_COLOR, 14)
		end)
	end

	model:PivotTo(CFrame.lookAt(greeter.Home, greeter.Home + greeter.Facing) * greeter.BuildPivot)
	model.Parent = folder
end

local function step(greeter: Greeter, now: number, here: Vector3?)
	local model = greeter.Model
	if not model then
		return
	end
	-- Turn to face a nearby player, otherwise face the spawn pad.
	if here and (here - greeter.Home).Magnitude < TURN_DISTANCE then
		local toward = Vector3.new(here.X - greeter.Home.X, 0, here.Z - greeter.Home.Z)
		if toward.Magnitude > 0.5 then
			greeter.Facing = greeter.Facing:Lerp(toward.Unit, 0.15)
		end
	end
	if now >= greeter.NextLineAt then
		greeter.NextLineAt = now + rng:NextNumber(4, 7)
		say(greeter, LINES[rng:NextInteger(1, #LINES)])
	end

	local t = now * 2.2 + greeter.Phase
	local bob = math.abs(math.sin(t)) * 0.25
	local wave = math.sin(t * 0.5) * 0.12 -- a friendly side-to-side sway
	local hop = 0
	if now < greeter.HopUntil then
		local progress = 1 - (greeter.HopUntil - now) / 0.45
		hop = math.sin(progress * math.pi) * 2.4
	end
	local facing = if greeter.Facing.Magnitude > 0.01 then greeter.Facing.Unit else Vector3.new(0, 0, 1)
	model:PivotTo(
		CFrame.lookAt(greeter.Home, greeter.Home + facing)
			* CFrame.new(0, bob + hop, 0)
			* CFrame.Angles(0, 0, wave)
			* greeter.BuildPivot
	)
end

function GreeterController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Greeters"
	folder.Parent = Workspace

	local hub = WorldLayout.Get("Hub").Center
	local padCentre = Vector3.new(hub.X, DAIS_Y, hub.Z + 17.5)
	for i, spec in GREETERS do
		local home = Vector3.new(hub.X, DAIS_Y, hub.Z) + spec.Offset
		local toPad = Vector3.new(padCentre.X - home.X, 0, padCentre.Z - home.Z)
		local greeter: Greeter = {
			Species = spec.Species,
			Rarity = spec.Rarity,
			Home = home,
			Model = nil,
			BuildPivot = CFrame.new(),
			Bubble = nil,
			Facing = if toPad.Magnitude > 0 then toPad.Unit else Vector3.new(0, 0, 1),
			HopUntil = 0,
			NextLineAt = os.clock() + i * 1.5,
			Phase = rng:NextNumber(0, math.pi * 2),
		}
		build(greeter)
		table.insert(greeters, greeter)
		BrainrotModels.WatchOverride(spec.Species, function()
			build(greeter)
		end)
	end

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 1 / 30 then
			return
		end
		accumulated = 0
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local here = if root and root:IsA("BasePart") then root.Position else nil
		if here and (here - padCentre).Magnitude > ANIMATE_DISTANCE then
			return -- nobody here to see them
		end
		local now = os.clock()
		for _, greeter in greeters do
			step(greeter, now, here)
		end
	end)
end

return GreeterController
