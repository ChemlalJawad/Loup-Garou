--!strict
-- Procedurally builds the whole physical world - hub/lobby, egg hatchery,
-- shop kiosk, CTF arena, the ground plate and connecting walkways beneath
-- them, and lighting/atmosphere - out of Parts only (no mesh/import
-- pipeline in this project). Single entry point Main.server.lua calls
-- (`require(MapBuilder).Init()`); every other file in this folder is a
-- private implementation detail required from here.
--
-- See docs/DESIGN_SYSTEM.md for the palette/lighting rationale and a map of
-- how the zones lay out relative to each other.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldKit = require(script.Parent.WorldKit)
local LightingSetup = require(script.Parent.LightingSetup)
local HubZone = require(script.Parent.HubZone)
local HatcheryZone = require(script.Parent.HatcheryZone)
local ShopZone = require(script.Parent.ShopZone)
local ArenaZone = require(script.Parent.ArenaZone)

local MapBuilder = {}

local WORLD_FOLDER_NAME = "World"

-- A single large plate under every zone so players never fall into the
-- void walking between them. Its visible top sits 2 studs below every
-- zone's own platform top (see the PLATFORM_TOP comment in HubZone.lua) so
-- zone platforms sit flush on top of it instead of z-fighting against it -
-- the gap only shows on the open ground between zones, which reads as a
-- deliberate "raised walkway" step rather than a bug.
local function buildGround(parent: Instance): Folder
	local groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = parent

	WorldKit.Part({
		Name = "BaseGround",
		Size = Vector3.new(280, 2, 540),
		Position = Vector3.new(0, -3, 110),
		Color = Color3.fromRGB(14, 14, 20),
		Material = Enum.Material.Slate,
		Parent = groundFolder,
	})

	return groundFolder
end

-- Straight walkway strip with neon edge trim connecting two zones. `Length`
-- runs along Z when `Axis == "Z"`, along X when `Axis == "X"`.
local function buildPath(
	parent: Instance,
	name: string,
	axis: "X" | "Z",
	center: Vector3,
	length: number,
	width: number,
	color: Color3
)
	local size = if axis == "Z" then Vector3.new(width, 2, length) else Vector3.new(length, 2, width)
	WorldKit.Part({
		Name = name,
		Size = size,
		Position = center + Vector3.new(0, -1, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	local edgeOffset = width / 2 - 0.3
	local trimSize = if axis == "Z" then Vector3.new(0.6, 0.4, length) else Vector3.new(length, 0.4, 0.6)
	local offsetVector = if axis == "Z" then Vector3.new(edgeOffset, 0.2, 0) else Vector3.new(0, 0.2, edgeOffset)

	WorldKit.Part({
		Name = name .. "TrimA",
		Size = trimSize,
		Position = center + offsetVector,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	WorldKit.Part({
		Name = name .. "TrimB",
		Size = trimSize,
		Position = center - offsetVector,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function buildPaths(parent: Instance)
	local pathsFolder = Instance.new("Folder")
	pathsFolder.Name = "Paths"
	pathsFolder.Parent = parent

	-- Hub (south edge Z=50) -> Hatchery (north edge Z=-83).
	buildPath(pathsFolder, "PathHubHatchery", "Z", Vector3.new(0, 0, -66.5), 33, 10, Theme.Color.AccentSecondary)

	-- Hub (east edge X=50) -> Shop (west edge X=78).
	buildPath(pathsFolder, "PathHubShop", "X", Vector3.new(64, 0, -20), 28, 10, Theme.Color.Robux)

	-- Hub (north edge Z=50, using +Z as "toward the arena") -> Arena (near edge Z=150).
	buildPath(pathsFolder, "PathHubArena", "Z", Vector3.new(0, 0, 100), 100, 14, Theme.Color.AccentPrimary)
end

function MapBuilder.Init()
	-- Idempotent: if a previous run already built the world (e.g. a script
	-- reload in Studio), tear it down first instead of doubling geometry.
	local existing = Workspace:FindFirstChild(WORLD_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = WORLD_FOLDER_NAME
	worldFolder.Parent = Workspace

	buildGround(worldFolder)
	buildPaths(worldFolder)

	HubZone.Build(worldFolder)
	HatcheryZone.Build(worldFolder)
	ShopZone.Build(worldFolder)
	ArenaZone.Build(worldFolder)

	LightingSetup.Apply()

	print("[MapBuilder] World generated: Hub, Hatchery, Shop, Arena.")
end

return MapBuilder
