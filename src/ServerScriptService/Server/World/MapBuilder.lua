--!strict
-- Builds the physical world: the shared ground plate, the paths between
-- zones, then every zone module, then lighting.
--
-- Zone modules are AUTO-DISCOVERED: any sibling ModuleScript in this folder
-- whose name ends in "Zone" and which returns a table with a `Build(parent)`
-- function is built automatically, ordered by its optional `Order` field.
-- That means adding a new area to the map never requires editing this file -
-- drop in `SomethingZone.lua` and it appears. Several zones were authored
-- independently, and this is what let that happen without them all fighting
-- over one registry list.
--
-- Each zone must confine its geometry to the rectangle allocated to it in
-- ReplicatedStorage.Shared.WorldLayout; see that file for the spatial
-- contract. See docs/DESIGN_SYSTEM.md for palette/lighting rationale.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)
local LightingSetup = require(script.Parent.LightingSetup)

local MapBuilder = {}

local WORLD_FOLDER_NAME = "World"

export type ZoneModule = {
	Build: (parent: Instance) -> (),
	Order: number?,
}

local function buildGround(parent: Instance): Folder
	local groundFolder = WorldKit.Group("Ground", parent)

	WorldKit.Part({
		Name = "BaseGround",
		Size = WorldLayout.GroundPlate.Size,
		Position = WorldLayout.GroundPlate.Center,
		Color = Color3.fromRGB(14, 14, 20),
		Material = Enum.Material.Slate,
		Parent = groundFolder,
	})

	return groundFolder
end

-- Straight walkway strip with neon edge trim connecting two zones. `axis` is
-- the direction the path runs along.
local function buildPath(
	parent: Instance,
	name: string,
	axis: "X" | "Z",
	center: Vector3,
	length: number,
	width: number,
	color: Color3
)
	local size = if axis == "Z" then Vector3.new(width, 1, length) else Vector3.new(length, 1, width)
	WorldKit.Part({
		Name = name,
		Size = size,
		Position = center + Vector3.new(0, -0.5, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	local edgeOffset = width / 2 - 0.3
	local trimSize = if axis == "Z" then Vector3.new(0.6, 0.3, length) else Vector3.new(length, 0.3, 0.6)
	local offsetVector = if axis == "Z" then Vector3.new(edgeOffset, 0, 0) else Vector3.new(0, 0, edgeOffset)

	for index, sign in { 1, -1 } do
		WorldKit.Part({
			Name = `{name}Trim{index}`,
			Size = trimSize,
			Position = center + offsetVector * sign,
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
	end
end

-- Paths are owned here rather than by any one zone, since each connects two
-- separately-authored zones and neither should reach into the other's rect.
local function buildPaths(parent: Instance)
	local paths = WorldKit.Group("Paths", parent)

	local hub = WorldLayout.Get("Hub")
	local hatchery = WorldLayout.Get("Hatchery")
	local commercial = WorldLayout.Get("Commercial")
	local arena = WorldLayout.Get("Arena")
	local plaza = WorldLayout.Get("Plaza")
	local lounge = WorldLayout.Get("Lounge")

	-- Hub -> Hatchery (south, -Z).
	local hubEdgeZ = hub.Center.Z - hub.Size.Z / 2
	local hatchEdgeZ = hatchery.Center.Z + hatchery.Size.Z / 2
	buildPath(
		paths,
		"PathHubHatchery",
		"Z",
		Vector3.new(0, WorldLayout.GroundY, (hubEdgeZ + hatchEdgeZ) / 2),
		hubEdgeZ - hatchEdgeZ,
		14,
		Theme.Color.AccentSecondary
	)

	-- Hub -> Commercial (east, +X).
	local hubEdgeX = hub.Center.X + hub.Size.X / 2
	local commEdgeX = commercial.Center.X - commercial.Size.X / 2
	buildPath(
		paths,
		"PathHubCommercial",
		"X",
		Vector3.new((hubEdgeX + commEdgeX) / 2, WorldLayout.GroundY, 0),
		commEdgeX - hubEdgeX,
		14,
		Theme.Color.Robux
	)

	-- Hub -> Plaza (west, -X).
	local hubEdgeWestX = hub.Center.X - hub.Size.X / 2
	local plazaEdgeX = plaza.Center.X + plaza.Size.X / 2
	buildPath(
		paths,
		"PathHubPlaza",
		"X",
		Vector3.new((hubEdgeWestX + plazaEdgeX) / 2, WorldLayout.GroundY, 0),
		hubEdgeWestX - plazaEdgeX,
		14,
		Theme.Color.AccentWarning
	)

	-- Hub -> Arena (north, +Z). The widest path: it's the route to the mode
	-- the game is built around, so it reads as the main street.
	local hubEdgeNorthZ = hub.Center.Z + hub.Size.Z / 2
	local arenaEdgeZ = arena.Center.Z - arena.Size.Z / 2
	buildPath(
		paths,
		"PathHubArena",
		"Z",
		Vector3.new(0, WorldLayout.GroundY, (hubEdgeNorthZ + arenaEdgeZ) / 2),
		arenaEdgeZ - hubEdgeNorthZ,
		22,
		Theme.Color.AccentPrimary
	)

	-- Commercial -> Lounge (south, -Z).
	local commEdgeSouthZ = commercial.Center.Z - commercial.Size.Z / 2
	local loungeEdgeZ = lounge.Center.Z + lounge.Size.Z / 2
	buildPath(
		paths,
		"PathCommercialLounge",
		"Z",
		Vector3.new(commercial.Center.X, WorldLayout.GroundY, (commEdgeSouthZ + loungeEdgeZ) / 2),
		commEdgeSouthZ - loungeEdgeZ,
		12,
		Theme.Color.AccentSecondary
	)
end

local function collectZoneModules(): { { Name: string, Module: ZoneModule } }
	local found = {}

	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and string.sub(child.Name, -4) == "Zone" then
			local ok, result = pcall(require, child)
			if not ok then
				warn(`[MapBuilder] failed to require zone "{child.Name}": {result}`)
			elseif type(result) ~= "table" or type(result.Build) ~= "function" then
				warn(`[MapBuilder] zone "{child.Name}" does not return a table with a Build(parent) function - skipping`)
			else
				table.insert(found, { Name = child.Name, Module = result :: ZoneModule })
			end
		end
	end

	table.sort(found, function(a, b)
		local orderA = a.Module.Order or 100
		local orderB = b.Module.Order or 100
		if orderA == orderB then
			return a.Name < b.Name
		end
		return orderA < orderB
	end)

	return found
end

function MapBuilder.Init()
	-- Idempotent: if a previous run already built the world (e.g. a script
	-- reload in Studio), tear it down first instead of doubling geometry.
	local existing = Workspace:FindFirstChild(WORLD_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local worldFolder = WorldKit.Group(WORLD_FOLDER_NAME, Workspace)

	buildGround(worldFolder)
	buildPaths(worldFolder)

	local zones = collectZoneModules()
	local built = {}
	for _, entry in zones do
		-- One failing zone must not take the whole map (and with it the CTF
		-- flag stands) down with it.
		local ok, err = pcall(entry.Module.Build, worldFolder)
		if ok then
			table.insert(built, entry.Name)
		else
			warn(`[MapBuilder] zone "{entry.Name}" errored during Build: {err}`)
		end
	end

	LightingSetup.Apply()

	print(`[MapBuilder] World generated with {#built} zone(s): {table.concat(built, ", ")}`)
end

return MapBuilder
