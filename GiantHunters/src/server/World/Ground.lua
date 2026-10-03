--!strict
-- The ground, all Smooth Terrain: the wilds get Roblox's swaying grass and
-- the river gets real water.
--
--   * Inside the wall: paved lots, cobbled ring roads and avenues, a pale
--     sandstone plaza.
--   * Outside: long grass broken up by patches of short grass and bare
--     earth, a dirt road from the gate, striped farm fields, a soft forest
--     floor, gentle rolling ground, and hills round the edge of the land.
--   * The river winds west to east across the north of town, under the wall
--     and out over the fields: stone banks in town, mud ones outside.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Layout = require(script.Parent.Layout)

local Ground = {}

local W = Config.World
local RES = 4
local DEPTH = 16 -- the land is a slab from y = -16 up to y = 0

local function disc(terrain: Terrain, radius: number, material: Enum.Material)
	terrain:FillCylinder(CFrame.new(0, -4, 0), 8, radius, material)
end

local function ring(terrain: Terrain, radius: number, width: number)
	disc(terrain, radius + width / 2, Enum.Material.Cobblestone)
	disc(terrain, radius - width / 2, Enum.Material.Pavement)
end

local function town(terrain: Terrain)
	local R = W.WallRadius
	disc(terrain, R + W.WallThickness / 2 + 4, Enum.Material.Cobblestone) -- the street round the inside of the wall
	disc(terrain, W.PerimeterRoad, Enum.Material.Pavement)
	-- Outermost ring first: each inner disc paints over the middle.
	for i = #W.RingRoads, 1, -1 do
		ring(terrain, W.RingRoads[i], W.RoadWidth)
	end
	disc(terrain, W.PlazaRadius + 6, Enum.Material.Cobblestone)
	disc(terrain, W.PlazaRadius, Enum.Material.Sandstone)
	-- Avenues from the plaza out to the wall.
	for _, degrees in W.AvenueAngles do
		local angle = math.rad(degrees)
		local from, to = W.PlazaRadius + 6, R + 4
		local centre = Geo.Polar(angle, (from + to) / 2, -4)
		local width = if degrees == 0 or degrees == 180 then W.AvenueWidth + 6 else W.AvenueWidth
		terrain:FillBlock(CFrame.new(centre) * CFrame.Angles(0, angle, 0), Vector3.new(width, 8, to - from), Enum.Material.Cobblestone)
	end
end

local function farmField(x: number, z: number): Enum.Material
	-- Fields are cells of a grid turned to face the gate road; each cell is
	-- ploughed stripes, ripe wheat or pasture.
	local turn = Layout.Farms.Angle
	local u = x * math.cos(turn) - z * math.sin(turn)
	local v = x * math.sin(turn) + z * math.cos(turn)
	local cellU, cellV = math.floor(u / 64), math.floor(v / 52)
	if (u % 64) < 3 or (v % 52) < 3 then
		return Enum.Material.Grass -- hedgerow strips between the fields
	end
	local pick = math.noise(cellU * 0.73 + 0.31, cellV * 0.61 + 0.17, 4.2)
	if pick > 0.12 then
		return if math.floor(v / 6) % 2 == 0 then Enum.Material.Ground else Enum.Material.LeafyGrass
	elseif pick > -0.18 then
		return Enum.Material.Sand -- wheat (sand, tinted gold below)
	end
	return Enum.Material.LeafyGrass
end

local function wilds(terrain: Terrain)
	local extent = W.LandRadius + 120
	local minXZ = -math.ceil(extent / RES) * RES
	local maxXZ = math.ceil(extent / RES) * RES
	local region = Region3.new(Vector3.new(minXZ, -RES, minXZ), Vector3.new(maxXZ, RES, maxXZ))
	local materials, occupancies = terrain:ReadVoxels(region, RES)
	local size = materials.Size
	local wallOut = W.WallRadius + W.WallThickness
	local gate = Geo.GateOuter()

	for i = 1, size.X do
		local x = minXZ + (i - 0.5) * RES
		for k = 1, size.Z do
			local z = minXZ + (k - 0.5) * RES
			local r = math.sqrt(x * x + z * z)
			if r > wallOut + 6 and materials[i][1][k] == Enum.Material.Grass then
				local p = Vector3.new(x, 0, z)
				local material = Enum.Material.Grass
				local flat = false
				local onRoad = z > wallOut - 4 and math.abs(x - Layout.RoadX(z)) < Layout.RoadHalfWidth
				if onRoad then
					material = Enum.Material.Ground
					flat = true
				elseif (p - gate).Magnitude < 46 and math.noise(x / 9, z / 9, 7.7) > -0.3 then
					material = Enum.Material.Ground -- the trampled apron outside the gate
					flat = true
				elseif Layout.InRegion(p, Layout.Farms) then
					material = farmField(x, z)
					flat = true
				elseif Layout.InRegion(p, Layout.Forest) or Layout.InRegion(p, Layout.GreatForest) or Layout.InRegion(p, Layout.Training) then
					local floor = math.noise(x / 26, z / 26, 2.9)
					material = if floor > 0.3 then Enum.Material.Mud elseif floor > -0.25 then Enum.Material.LeafyGrass else Enum.Material.Grass
				else
					local lush = math.noise(x / 70, z / 70, 3.7)
					local bare = math.noise(x / 38, z / 38, 8.1)
					if lush > 0.22 then
						material = Enum.Material.LeafyGrass
					elseif bare < -0.48 then
						material = Enum.Material.Ground
					elseif math.noise(x / 17, z / 17, 6.3) > 0.62 then
						material = Enum.Material.Rock
					end
				end
				materials[i][1][k] = material

				-- Rolling ground, flat by the wall, the road and the farms.
				if not flat then
					local fade = math.clamp((r - wallOut - 20) / 40, 0, 1)
					local roll = math.noise(x / 52, z / 52, 5.9) * 0.7 + math.noise(x / 19, z / 19, 2.2) * 0.3
					local height = math.min(math.max(roll, 0) * 2.5, 1) * 2.6 * fade
					if height > 0.05 then
						materials[i][2][k] = material
						occupancies[i][2][k] = math.clamp(height / RES, 0, 1)
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, RES, materials, occupancies)
end

local function hills(terrain: Terrain, rng: Random)
	-- A ring of grassy hills closes the land in; a few rockier ones.
	for i = 1, 96 do
		local angle = (i / 96) * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local radius = rng:NextNumber(60, 120)
		local distance = W.LandRadius + rng:NextNumber(10, 90)
		local centre = Geo.Polar(angle, distance, -radius * rng:NextNumber(0.45, 0.7))
		terrain:FillBall(centre, radius, if rng:NextNumber() < 0.2 then Enum.Material.Rock else Enum.Material.Grass)
	end
end

-- Dirt roads across the plains (Layout.Roads), and the castle's hill.
local function roads(terrain: Terrain)
	for _, road in Layout.Roads do
		for i = 1, #road - 1 do
			local a, b = road[i], road[i + 1]
			local middle = (a + b) / 2
			local frame = CFrame.lookAt(Vector3.new(middle.X, -4, middle.Z), Vector3.new(b.X, -4, b.Z))
			terrain:FillBlock(frame, Vector3.new(Layout.RoadHalfWidth * 2, 8, (b - a).Magnitude + Layout.RoadHalfWidth * 2), Enum.Material.Ground)
		end
	end
end

local function castleHill(terrain: Terrain)
	local castle = Layout.Castle
	local centre = Geo.Polar(castle.Angle, castle.Radius)
	local radius = castle.HillRadius
	terrain:FillBall(Vector3.new(centre.X, castle.Top - radius, centre.Z), radius, Enum.Material.Grass)
	-- A rocky crown where the castle stands.
	terrain:FillCylinder(CFrame.new(centre.X, castle.Top - 6, centre.Z), 12, 52, Enum.Material.Rock)
end

local function river(terrain: Terrain)
	local river = W.River
	local reach = W.LandRadius + 100
	local wallOut = W.WallRadius + W.WallThickness
	for x = -reach, reach, RES do
		local z = Geo.RiverZ(x)
		local inTown = math.sqrt(x * x + z * z) < wallOut + 8
		local bank = if inTown then Enum.Material.Slate else Enum.Material.Mud
		terrain:FillBlock(CFrame.new(x, -6, z), Vector3.new(RES + 2, 12, river.Width + 10), bank)
		terrain:FillBlock(CFrame.new(x, -6, z), Vector3.new(RES + 2, 12, river.Width), Enum.Material.Air)
		terrain:FillBlock(CFrame.new(x, (river.WaterY - 12) / 2, z), Vector3.new(RES + 2, river.WaterY + 12, river.Width), Enum.Material.Water)
	end
end

function Ground.Build(rng: Random)
	local terrain = Workspace.Terrain
	terrain:Clear()
	local extent = (W.LandRadius + 140) * 2
	terrain:FillBlock(CFrame.new(0, -DEPTH / 2, 0), Vector3.new(extent, DEPTH, extent), Enum.Material.Grass)
	town(terrain)
	wilds(terrain)
	roads(terrain)
	hills(terrain, rng)
	castleHill(terrain)
	river(terrain)

	terrain.Decoration = true
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(98, 156, 70))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(122, 170, 80))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(140, 110, 78))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(104, 84, 62))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(214, 182, 96)) -- wheat
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(132, 128, 120))
	terrain:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(176, 166, 150))
	terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(146, 138, 126))
	terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(214, 198, 168))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(120, 116, 110))
	terrain.WaterColor = Color3.fromRGB(64, 118, 128)
	terrain.WaterTransparency = 0.45
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8

	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 250, 244)
	clouds.Parent = terrain
end

return Ground
