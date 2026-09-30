--!strict
-- The sky: the Lucky Rainbow arc while that event is on, plus puffy
-- cartoon part clouds as a fallback when there are no volumetric terrain
-- Clouds (see TerrainZone).
--
-- Client-only, like the Parade walkers: each cloud's position is a pure
-- function of workspace:GetServerTimeNow(), so every player sees the same
-- clouds in the same place with zero network traffic, and the server never
-- touches them. Clouds only move 10 times a second - at this drift speed
-- that is indistinguishable from every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EventConfig = require(ReplicatedStorage.Shared.Events.EventConfig)

local SkyController = {}

local CLOUD_COUNT = 14
local CLOUD_SEED = 7 -- same seed on every client = same clouds for everyone
local DRIFT_SPEED = 3 -- studs per second, along +X
local SPAN_X = 1600 -- clouds wrap around within this width
local UPDATE_INTERVAL = 0.1

local RAINBOW_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(255, 230, 80),
	Color3.fromRGB(100, 220, 110),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(110, 110, 240),
	Color3.fromRGB(190, 110, 240),
}
local RAINBOW_RADIUS = 260
local RAINBOW_BAND = 7
local RAINBOW_SEGMENTS = 22

type Cloud = {
	Model: Model,
	StartX: number,
	Y: number,
	Z: number,
}

local clouds: { Cloud } = {}
local rainbow: Model? = nil

local function cloudPart(parent: Instance, offset: Vector3, diameter: number): Part
	local part = Instance.new("Part")
	part.Name = "Puff"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Transparency = 0.08
	part.CFrame = CFrame.new(offset)
	part.Parent = parent
	return part
end

local function buildClouds(folder: Folder)
	local rng = Random.new(CLOUD_SEED)
	local centre = WorldLayout.GroundPlate.Center
	for i = 1, CLOUD_COUNT do
		local model = Instance.new("Model")
		model.Name = `Cloud{i}`
		local scale = rng:NextNumber(0.8, 1.6)
		local core = cloudPart(model, Vector3.zero, 26 * scale)
		model.PrimaryPart = core
		for _ = 1, rng:NextInteger(3, 5) do
			cloudPart(
				model,
				Vector3.new(rng:NextNumber(-22, 22) * scale, rng:NextNumber(-4, 5) * scale, rng:NextNumber(-10, 10) * scale),
				rng:NextNumber(14, 22) * scale
			)
		end
		model.Parent = folder
		table.insert(clouds, {
			Model = model,
			StartX = rng:NextNumber(0, SPAN_X),
			Y = rng:NextNumber(150, 210),
			Z = centre.Z + rng:NextNumber(-520, 520),
		})
	end
end

local function placeClouds(serverNow: number)
	local centreX = WorldLayout.GroundPlate.Center.X
	for _, cloud in clouds do
		local x = (cloud.StartX + serverNow * DRIFT_SPEED) % SPAN_X - SPAN_X / 2 + centreX
		cloud.Model:PivotTo(CFrame.new(x, cloud.Y, cloud.Z))
	end
end

-- A seven-band arc north of the Arena, facing the Central Plaza: the first
-- thing you see looking up the main path.
local function showRainbow(folder: Folder)
	if rainbow then
		return
	end
	local model = Instance.new("Model")
	model.Name = "LuckyRainbow"
	local plate = WorldLayout.GroundPlate
	local base = Vector3.new(0, WorldLayout.GroundY - 30, plate.Center.Z + plate.Size.Z / 2 + 80)
	for band, color in RAINBOW_COLORS do
		local radius = RAINBOW_RADIUS - (band - 1) * RAINBOW_BAND
		local segmentLength = (math.pi * radius / RAINBOW_SEGMENTS) * 1.08 -- slight overlap hides seams
		for s = 0, RAINBOW_SEGMENTS - 1 do
			local angle = math.pi * (s + 0.5) / RAINBOW_SEGMENTS
			local position = base + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			local part = Instance.new("Part")
			part.Name = `Band{band}`
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Transparency = 0.35
			part.Size = Vector3.new(segmentLength, RAINBOW_BAND, 1)
			-- Tangent to the arc: rotate about Z by the angle + 90 degrees.
			part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, angle + math.pi / 2)
			part.Parent = model
		end
	end
	model.Parent = folder
	rainbow = model
end

local function hideRainbow()
	if rainbow then
		rainbow:Destroy()
		rainbow = nil
	end
end

function SkyController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Sky"
	folder.Parent = Workspace

	-- TerrainZone adds engine-rendered volumetric Clouds, which look far
	-- better; the cartoon part clouds are only the fallback for when terrain
	-- generation failed. Checked after a short wait so the Terrain's Clouds
	-- child has time to replicate.
	task.delay(5, function()
		if not Workspace.Terrain:FindFirstChildOfClass("Clouds") then
			buildClouds(folder)
			placeClouds(Workspace:GetServerTimeNow())
		end
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < UPDATE_INTERVAL then
			return
		end
		accumulated = 0
		local now = Workspace:GetServerTimeNow()
		placeClouds(now)

		-- Polled rather than attribute-signalled so the rainbow also fades
		-- on time if the server's "clear" never arrives.
		if EventConfig.IsLuckyRainbow(now) then
			showRainbow(folder)
		else
			hideRainbow()
		end
	end)
end

return SkyController
