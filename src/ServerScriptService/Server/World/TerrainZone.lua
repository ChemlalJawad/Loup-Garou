--!strict
-- Smooth Terrain ground: the single biggest "looks real" upgrade available
-- without any uploaded assets. Roblox's grass material with Decoration on
-- grows animated grass blades that sway in the wind, and terrain water gives
-- the Lily Pond real waves, reflections and swimming.
--
--   * Grass over the whole plate.
--   * Short, blade-free lawn under every zone rect and every path rect from
--     PathRegistry, so grass never pokes up through a floor.
--   * A dug-out pond basin at WorldLayout.Landmarks.LilyPond: sand beach,
--     sand bed, water just below grass level.
--   * Volumetric Clouds and tuned water/grass colours.
--
-- Order 140: after every real zone (so zone rects are final) and after
-- MapBuilder's paths, before BiomeZone (150), which reads the
-- "HatchWarsTerrain" attribute to swap its part-based pond water, hills and
-- meadow patches for terrain versions. If anything here fails, the
-- attribute stays unset and BiomeZone falls back to parts - and MapBuilder's
-- BaseGround part stays as the floor - so the world is never left without
-- ground.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local PathRegistry = require(script.Parent.PathRegistry)

local TerrainZone = {}
TerrainZone.Order = 140

TerrainZone.ATTRIBUTE = "HatchWarsTerrain"

local SURFACE_Y = WorldLayout.GroundY - 0.05 -- a hair under paths/floors, like BaseGround was
local LAYER = 12 -- thick enough that the pond basin never digs through

local POND_RADIUS = 21
local BEACH_RADIUS = 26
local POND_DEPTH = 6
local WATER_SURFACE_BELOW_GRASS = 0.5

local GRASS = Color3.fromRGB(96, 170, 88)

local function surfaceLayer(terrain: Terrain, centre: Vector3, size: Vector3, material: Enum.Material)
	terrain:FillBlock(
		CFrame.new(centre.X, SURFACE_Y - LAYER / 2, centre.Z),
		Vector3.new(size.X, LAYER, size.Z),
		material
	)
end

local function build(parent: Instance)
	local terrain = Workspace.Terrain
	terrain:Clear()

	local plate = WorldLayout.GroundPlate
	surfaceLayer(terrain, plate.Center, plate.Size, Enum.Material.Grass)

	-- No grass blades under anything with a floor: Terrain.Decoration only
	-- grows blades on Grass, so zone and path footprints get LeafyGrass
	-- tinted the same green - it reads as the same lawn, mown short.
	for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		surfaceLayer(terrain, zone.Center, zone.Size, Enum.Material.LeafyGrass)
	end
	-- Paths (and the pond trail) are registered by MapBuilder before any
	-- zone builds. A 2-stud margin keeps blades off the path edges.
	for _, rect in PathRegistry.GetRects() do
		surfaceLayer(terrain, rect.Center, rect.Size + Vector3.new(4, 0, 4), Enum.Material.LeafyGrass)
	end

	-- The pond: beach ring, dig the basin, sand bed, then water.
	local pond = WorldLayout.Landmarks.LilyPond
	local function disc(topY: number, height: number, radius: number, material: Enum.Material)
		terrain:FillCylinder(CFrame.new(pond.X, topY - height / 2, pond.Z), height, radius, material)
	end
	disc(SURFACE_Y, 4, BEACH_RADIUS, Enum.Material.Sand)
	disc(SURFACE_Y, POND_DEPTH, POND_RADIUS, Enum.Material.Air)
	disc(SURFACE_Y - POND_DEPTH, 2, POND_RADIUS, Enum.Material.Sand)
	disc(SURFACE_Y - WATER_SURFACE_BELOW_GRASS, POND_DEPTH - WATER_SURFACE_BELOW_GRASS, POND_RADIUS, Enum.Material.Water)

	-- Look: grass blades, colours matched to the part-built world, and water
	-- tuned bright and gentle (a pond, not an ocean).
	terrain.Decoration = true
	terrain:SetMaterialColor(Enum.Material.Grass, GRASS)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, GRASS)
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(150, 118, 84))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(232, 214, 160))
	terrain.WaterColor = Color3.fromRGB(60, 165, 215)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.5
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6

	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain

	-- Terrain is the ground now; the flat fallback part would only z-fight
	-- with it (and show through the pond basin).
	local ground = parent:FindFirstChild("Ground")
	local baseGround = ground and ground:FindFirstChild("BaseGround")
	if baseGround then
		baseGround:Destroy()
	end

	terrain:SetAttribute(TerrainZone.ATTRIBUTE, true)
end

function TerrainZone.Build(parent: Instance)
	Workspace.Terrain:SetAttribute(TerrainZone.ATTRIBUTE, nil)
	local ok, err = pcall(build, parent)
	if not ok then
		warn(`[TerrainZone] terrain generation failed, keeping the part ground: {err}`)
		Workspace.Terrain:SetAttribute(TerrainZone.ATTRIBUTE, nil)
	end
end

return TerrainZone
