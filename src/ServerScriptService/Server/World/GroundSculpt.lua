--!strict
-- Makes the open lawn look hand-built instead of a flat green sheet, using
-- the techniques Roblox's best-looking maps (and the DevForum terraining
-- guides) rely on:
--
--   1. Material patchwork - big soft patches of short, sunny "leafy" grass
--      among the long swaying grass, and the odd bare-earth spot.
--   2. Gentle height variation - the ground rolls by up to ~1.6 studs.
--   3. Worn edges - a broken band of dirt where grass meets a path or a
--      building ("grass doesn't grow right up against them").
--
-- Everything is driven by math.noise with fixed offsets, so every server
-- gets the same ground. Flat and untouched near anything built: zones,
-- paths, the themed wilds and the landmarks all get a clearance that the
-- bumps fade in from, so floors, lamp posts and signs never sit on a slope.
--
-- Done in one ReadVoxels/WriteVoxels pass over the surface layer (4-stud
-- voxels) instead of thousands of FillBlock calls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local PathRegistry = require(script.Parent.PathRegistry)

local GroundSculpt = {}

local RES = 4
local MAX_BUMP = 1.6 -- studs of extra height at most
local FLAT_CLEARANCE = 6 -- studs around built things that stay perfectly flat
local FADE = 16 -- studs over which bumps then fade in
local EDGE_BAND = 5 -- studs of worn dirt just outside paths and zones

type Rect = { Center: Vector3, Size: Vector3 }
type Circle = { Center: Vector3, Radius: number }

local function rectDistance(x: number, z: number, rect: Rect): number
	local dx = math.max(math.abs(x - rect.Center.X) - rect.Size.X / 2, 0)
	local dz = math.max(math.abs(z - rect.Center.Z) - rect.Size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Distance to the nearest built thing (0 = on/inside it), and separately to
-- the nearest path or zone (for the worn-dirt band).
local function distances(x: number, z: number, built: { Rect }, edged: { Rect }, circles: { Circle }): (number, number)
	local nearest = math.huge
	local nearestEdge = math.huge
	for _, rect in built do
		nearest = math.min(nearest, rectDistance(x, z, rect))
	end
	for _, rect in edged do
		nearestEdge = math.min(nearestEdge, rectDistance(x, z, rect))
	end
	for _, circle in circles do
		local d = math.max((Vector3.new(x, 0, z) - Vector3.new(circle.Center.X, 0, circle.Center.Z)).Magnitude - circle.Radius, 0)
		nearest = math.min(nearest, d)
	end
	return math.min(nearest, nearestEdge), nearestEdge
end

-- `surfaceY` is where the flat lawn's surface sits (just under GroundY).
function GroundSculpt.Apply(terrain: Terrain, surfaceY: number)
	local plate = WorldLayout.GroundPlate

	-- Everything that must stay flat, and the subset that gets worn edges.
	local edged: { Rect } = {}
	for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		table.insert(edged, { Center = zone.Center, Size = zone.Size })
	end
	for _, rect in PathRegistry.GetRects() do
		table.insert(edged, rect)
	end
	local built: { Rect } = {}
	for _, rect in WorldLayout.Wilds :: { [string]: Rect } do
		table.insert(built, rect)
	end
	local landmarks = WorldLayout.Landmarks
	local circles: { Circle } = {
		{ Center = landmarks.LilyPond, Radius = 36 },
		{ Center = landmarks.StatueWest, Radius = 14 },
		{ Center = landmarks.StatueEast, Radius = 14 },
	}

	-- Two voxel layers: the lawn's surface layer, and the one above it that
	-- the bumps grow into. Grid-aligned, covering the whole plate.
	local minX = math.floor((plate.Center.X - plate.Size.X / 2) / RES) * RES
	local maxX = math.ceil((plate.Center.X + plate.Size.X / 2) / RES) * RES
	local minZ = math.floor((plate.Center.Z - plate.Size.Z / 2) / RES) * RES
	local maxZ = math.ceil((plate.Center.Z + plate.Size.Z / 2) / RES) * RES
	local baseY = math.floor(surfaceY / RES) * RES -- bottom of the surface layer's voxel
	local region = Region3.new(Vector3.new(minX, baseY, minZ), Vector3.new(maxX, baseY + RES * 2, maxZ))
	local materials, occupancies = terrain:ReadVoxels(region, RES)
	local size = materials.Size

	for i = 1, size.X do
		local x = minX + (i - 0.5) * RES
		for k = 1, size.Z do
			local z = minZ + (k - 0.5) * RES
			-- Only open lawn is reshaped; zones/paths are already LeafyGrass,
			-- and anything else (sand, water, wilds) is left alone.
			if materials[i][1][k] == Enum.Material.Grass then
				local nearest, nearestEdge = distances(x, z, built, edged, circles)

				-- 1. Material patchwork.
				local lush = math.noise(x / 70, z / 70, 3.7)
				local bare = math.noise(x / 38, z / 38, 8.1)
				local material = Enum.Material.Grass
				if lush > 0.22 then
					material = Enum.Material.LeafyGrass
				elseif bare < -0.46 then
					material = Enum.Material.Ground
				end

				-- 3. Worn edges: dirt hugging paths and buildings, broken up
				-- by noise so it reads as footfall, not a painted border.
				if nearestEdge <= EDGE_BAND and math.noise(x / 11, z / 11, 1.3) > 0.12 then
					material = Enum.Material.Ground
				end
				materials[i][1][k] = material

				-- 2. Rolling ground, flat near anything built.
				local fade = math.clamp((nearest - FLAT_CLEARANCE) / FADE, 0, 1)
				if fade > 0 then
					local roll = math.noise(x / 45, z / 45, 5.9) * 0.7 + math.noise(x / 18, z / 18, 2.2) * 0.3
					local height = math.min(math.max(roll, 0) * 2.5, 1) * MAX_BUMP * fade
					if height > 0.05 then
						-- The surface layer is already (almost) full; the bump
						-- is partial occupancy in the voxel above it.
						materials[i][2][k] = material
						occupancies[i][2][k] = math.clamp(height / RES, 0, 1)
					end
				end
			end
		end
	end

	terrain:WriteVoxels(region, RES, materials, occupancies)
end

return GroundSculpt
