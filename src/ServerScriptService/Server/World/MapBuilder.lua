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
local PathRegistry = require(script.Parent.PathRegistry)

local MapBuilder = {}

local WORLD_FOLDER_NAME = "World"

export type ZoneModule = {
	Build: (parent: Instance) -> (),
	Order: number?,
}

local function buildGround(parent: Instance): Folder
	local groundFolder = WorldKit.Group("Ground", parent)

	-- Grass between the zones: every zone brings its own floor, so this only
	-- shows on the open ground between them. A dark slate plate made the
	-- in-between read as a void; a bright lawn (plus LandscapeZone's trees
	-- and flowers) makes the whole map read as one friendly park.
	WorldKit.Part({
		Name = "BaseGround",
		Size = WorldLayout.GroundPlate.Size,
		Position = WorldLayout.GroundPlate.Center,
		Color = Color3.fromRGB(96, 170, 88),
		Material = Enum.Material.Grass,
		Parent = groundFolder,
	})

	return groundFolder
end

-- Straight walkway strip with neon edge trim connecting two zones. `axis` is
-- the direction the path runs along. `label`, when given, puts a floating
-- signpost at the path's midpoint - used for zones that aren't directly
-- reachable from the Hub's four gateways, so players (young ones especially)
-- can always follow a sign to every activity.
local function buildPath(
	parent: Instance,
	name: string,
	axis: "X" | "Z",
	center: Vector3,
	length: number,
	width: number,
	color: Color3,
	label: string?
)
	local size = if axis == "Z" then Vector3.new(width, 1, length) else Vector3.new(length, 1, width)
	PathRegistry.Add(center, size)
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

	-- Lamp posts every ~24 studs, alternating sides and set back beyond the
	-- neon edge trim (never on the walkway itself), so the walk between zones
	-- isn't just a bare colored strip - this was the visually weakest link
	-- between an otherwise-detailed set of zones. Cap color matches the
	-- path's own neon trim for continuity with the zone it leads into.
	local postSpacing = 24
	local postCount = math.max(1, math.floor(length / postSpacing))
	local alongAxis = if axis == "Z" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local perpUnit = if axis == "Z" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local postSideOffset = edgeOffset + 1.5 -- beyond the trim, off the walkway

	for i = 1, postCount do
		-- Centered spacing: posts sit at fractional offsets from the path's own
		-- centre rather than from one end, so a path never gets a lonely post
		-- crammed right against a zone entrance.
		local t = (i - 0.5) / postCount - 0.5
		local along = alongAxis * (t * length)
		local sign = if i % 2 == 0 then 1 else -1
		local lampPost = WorldKit.Pillar({
			Name = `{name}Lamp{i}`,
			Position = center + along + perpUnit * postSideOffset * sign,
			Height = 9,
			Thickness = 0.7,
			Color = Color3.fromRGB(36, 36, 50),
			CapColor = color,
			Parent = parent,
		})
		-- A real pool of light on the walkway at night. Tagged as decor by
		-- WorldKit.Light, so LightingController switches it off in daylight
		-- and on low graphics quality.
		WorldKit.Light({
			Name = "LampGlow",
			Color = color:Lerp(Color3.new(1, 1, 1), 0.45),
			Brightness = 1.6,
			Range = 18,
			Parent = lampPost,
		})
	end

	if label then
		local signPost = WorldKit.Part({
			Name = `{name}SignPost`,
			Size = Vector3.new(1, 7, 1),
			Position = center + perpUnit * (edgeOffset + 3) + Vector3.new(0, 3.5, 0),
			Color = Color3.fromRGB(36, 36, 50),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
		WorldKit.Sign({
			Name = `{name}Sign`,
			Adornee = signPost,
			Text = label,
			Color = color,
			Size = UDim2.new(0, 320, 0, 50),
			TextSize = 24,
			StudsOffset = Vector3.new(0, 5.5, 0),
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
	local parade = WorldLayout.Get("Parade")
	local funPark = WorldLayout.Get("FunPark")

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
		Theme.Color.Robux,
		"MARKET  /  FUN PARK"
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
		Theme.Color.AccentWarning,
		"HALL OF FAME  /  PARADE"
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

	-- Plaza -> Parade (south, -Z). Signed: the Parade is the headline
	-- activity for new players and isn't visible from the Hub.
	local plazaEdgeSouthZ = plaza.Center.Z - plaza.Size.Z / 2
	local paradeEdgeNorthZ = parade.Center.Z + parade.Size.Z / 2
	buildPath(
		paths,
		"PathPlazaParade",
		"Z",
		Vector3.new(parade.Center.X, WorldLayout.GroundY, (plazaEdgeSouthZ + paradeEdgeNorthZ) / 2),
		plazaEdgeSouthZ - paradeEdgeNorthZ,
		16,
		Theme.Color.AccentDanger,
		"BRAINROT PARADE"
	)

	-- Parade -> Hatchery (east, +X): closes the loop so players can walk
	-- Hub -> Hall of Fame -> Parade -> Hatchery -> Hub without backtracking.
	local paradeEdgeEastX = parade.Center.X + parade.Size.X / 2
	local hatcheryEdgeWestX = hatchery.Center.X - hatchery.Size.X / 2
	buildPath(
		paths,
		"PathParadeHatchery",
		"X",
		Vector3.new((paradeEdgeEastX + hatcheryEdgeWestX) / 2, WorldLayout.GroundY, WorldLayout.Doors.HatcheryWest.Z),
		hatcheryEdgeWestX - paradeEdgeEastX,
		12,
		Theme.Color.AccentSecondary,
		"HATCHERY"
	)

	-- Commercial -> Fun Park (north, +Z).
	local commEdgeNorthZ = commercial.Center.Z + commercial.Size.Z / 2
	local funParkEdgeSouthZ = funPark.Center.Z - funPark.Size.Z / 2
	buildPath(
		paths,
		"PathCommercialFunPark",
		"Z",
		Vector3.new(funPark.Center.X, WorldLayout.GroundY, (commEdgeNorthZ + funParkEdgeSouthZ) / 2),
		funParkEdgeSouthZ - commEdgeNorthZ,
		16,
		Theme.Color.AccentInfo,
		"FUN PARK"
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
	PathRegistry.Clear()

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
