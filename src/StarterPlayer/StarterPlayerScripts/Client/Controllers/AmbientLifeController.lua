--!strict
-- Ambient life: a handful of Brainrots wandering the lawns between zones,
-- waddling to a spot, idling, wandering on. Tap one to pet it and it hops
-- with a burst of hearts. Pure decoration - no reward, so there's nothing
-- to farm and nothing the server needs to know about.
--
-- Entirely client-side: each player's wanderers are their own local models,
-- so they cost zero network traffic and zero server time. Each client only
-- animates the wanderers near its own player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local BrainrotModels = require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
local FX = require(ReplicatedStorage.Shared.Effects.FX)

local AmbientLifeController = {}

local WANDERER_COUNT = 10
local HOME_RADIUS_FROM_HUB = 170 -- wanderers live on the lawns around the Hub, where players are
local WANDER_RADIUS = 18
local ZONE_MARGIN = 10 -- keep out of buildings
local WALK_SPEED = 4
local ANIMATE_DISTANCE = 220
local UPDATE_INTERVAL = 1 / 30
local HEART_COLOR = Color3.fromRGB(255, 110, 160)

type Wanderer = {
	Model: Model,
	BuildPivot: CFrame,
	Home: Vector3,
	Position: Vector3,
	Target: Vector3,
	Facing: Vector3,
	IdleUntil: number,
	HopUntil: number,
	Phase: number,
}

local localPlayer = Players.LocalPlayer
local rng = Random.new()
local wanderers: { Wanderer } = {}

-- The lawn rolls gently (GroundSculpt): follow the terrain surface.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Workspace.Terrain }

local function groundHeight(position: Vector3): number
	local hit = Workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -24, 0), groundParams)
	return if hit then hit.Position.Y else WorldLayout.GroundY
end

local function insideAnyZone(position: Vector3): boolean
	for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		if
			math.abs(position.X - zone.Center.X) <= zone.Size.X / 2 + ZONE_MARGIN
			and math.abs(position.Z - zone.Center.Z) <= zone.Size.Z / 2 + ZONE_MARGIN
		then
			return true
		end
	end
	return false
end

local function randomLawnPoint(around: Vector3, radius: number): Vector3?
	for _ = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, radius)
		local candidate = around + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		candidate = Vector3.new(candidate.X, WorldLayout.GroundY, candidate.Z)
		if not insideAnyZone(candidate) then
			return candidate
		end
	end
	return nil
end

local function pickSpecies(): (string, string)
	-- Mostly Commons and Rares with the odd Epic: the lawns should feel
	-- lived-in, not like a free showcase of the rarest characters.
	local roll = rng:NextNumber()
	local rarity = if roll < 0.6 then "Common" elseif roll < 0.92 then "Rare" else "Epic"
	return EggConfig.RollSpecies(rarity, rng), rarity
end

local function spawnWanderer(folder: Folder, home: Vector3)
	local species, rarity = pickSpecies()
	local ok, modelOrError = pcall(BrainrotModels.BuildStatic, species, rarity)
	if not ok or typeof(modelOrError) ~= "Instance" then
		return
	end
	local model = modelOrError :: Model
	local buildPivot = model:GetPivot()

	local wanderer: Wanderer = {
		Model = model,
		BuildPivot = buildPivot,
		Home = home,
		Position = home,
		Target = home,
		Facing = Vector3.new(0, 0, -1),
		IdleUntil = os.clock() + rng:NextNumber(0, 3),
		HopUntil = 0,
		Phase = rng:NextNumber(0, math.pi * 2),
	}

	local primary = model.PrimaryPart
	if primary then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pet"
		prompt.ObjectText = EggConfig.DisplayName(species)
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = primary
		prompt.Triggered:Connect(function()
			wanderer.HopUntil = os.clock() + 0.45
			wanderer.IdleUntil = os.clock() + 2 -- stop and enjoy it
			FX.Burst(wanderer.Position + Vector3.new(0, 3, 0), HEART_COLOR, 14)
			FX.FloatingText(wanderer.Position + Vector3.new(0, 5, 0), "<3", HEART_COLOR)
		end)
	end

	model:PivotTo(CFrame.new(home) * buildPivot)
	model.Parent = folder
	table.insert(wanderers, wanderer)
end

local function step(wanderer: Wanderer, now: number, dt: number)
	if now >= wanderer.IdleUntil then
		local toTarget = wanderer.Target - wanderer.Position
		local distance = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
		if distance < 0.5 then
			-- Arrived: idle a moment, then choose somewhere new near home.
			wanderer.IdleUntil = now + rng:NextNumber(2, 5)
			wanderer.Target = randomLawnPoint(wanderer.Home, WANDER_RADIUS) or wanderer.Home
		else
			-- Walk on the flat plane, then sit on the terrain surface.
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
			local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			wanderer.Facing = direction
			local moved = wanderer.Position + direction * math.min(flat.Magnitude, WALK_SPEED * dt)
			wanderer.Position = Vector3.new(moved.X, groundHeight(moved), moved.Z)
		end
	end

	local walking = now >= wanderer.IdleUntil
	local t = now * 6 + wanderer.Phase
	local bob = if walking then math.abs(math.sin(t)) * 0.3 else math.sin(t * 0.3) * 0.05
	local lean = if walking then math.sin(t) * 0.08 else 0
	local hop = 0
	if now < wanderer.HopUntil then
		local progress = 1 - (wanderer.HopUntil - now) / 0.45
		hop = math.sin(progress * math.pi) * 2.2
	end

	local base = CFrame.lookAt(wanderer.Position, wanderer.Position + wanderer.Facing)
	wanderer.Model:PivotTo(base * CFrame.new(0, bob + hop, 0) * CFrame.Angles(0, 0, lean) * wanderer.BuildPivot)
end

function AmbientLifeController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "AmbientLife"
	folder.Parent = Workspace

	local hubCenter = WorldLayout.Get("Hub").Center
	for _ = 1, WANDERER_COUNT do
		local home = randomLawnPoint(hubCenter, HOME_RADIUS_FROM_HUB)
		if home then
			spawnWanderer(folder, home)
		end
	end

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < UPDATE_INTERVAL then
			return
		end
		local stepDt = accumulated
		accumulated = 0

		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local now = os.clock()
		for _, wanderer in wanderers do
			-- Far-away wanderers freeze in place: nobody can see them move.
			if (wanderer.Position - root.Position).Magnitude <= ANIMATE_DISTANCE then
				step(wanderer, now, stepDt)
			end
		end
	end)
end

return AmbientLifeController
