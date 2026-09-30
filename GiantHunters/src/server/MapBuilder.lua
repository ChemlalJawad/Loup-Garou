--!strict
-- Builds the arena from code: a square walled city with streets of houses
-- and towers (everything is grappleable), a forest of giant trees in the
-- east quarter, a central plaza with the spawn, and supply stations.
--
-- Built for the grapple: lots of tall, spread-out anchor points, with open
-- streets between them for giants to walk down.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local ROOF_COLORS = {
	Color3.fromRGB(176, 72, 58),
	Color3.fromRGB(150, 90, 60),
	Color3.fromRGB(90, 110, 140),
	Color3.fromRGB(120, 60, 50),
}
local WALL_COLORS = {
	Color3.fromRGB(236, 226, 206),
	Color3.fromRGB(222, 204, 176),
	Color3.fromRGB(210, 196, 180),
	Color3.fromRGB(240, 234, 220),
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function house(parent: Instance, base: Vector3, width: number, depth: number, height: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "House"
	part({
		Name = "Walls",
		Size = Vector3.new(width, height, depth),
		Position = base + Vector3.new(0, height / 2, 0),
		Color = WALL_COLORS[rng:NextInteger(1, #WALL_COLORS)],
		Material = Enum.Material.Plaster,
		Parent = model,
	})
	-- Timber frame bands, the cosy old-town look.
	for _, y in { height * 0.33, height * 0.66 } do
		part({
			Name = "Beam",
			Size = Vector3.new(width + 0.4, 0.8, depth + 0.4),
			Position = base + Vector3.new(0, y, 0),
			Color = Color3.fromRGB(96, 66, 44),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CastShadow = false,
			Parent = model,
		})
	end
	-- Pitched roof from two wedges.
	local roofColor = ROOF_COLORS[rng:NextInteger(1, #ROOF_COLORS)]
	local roofHeight = math.min(width, depth) * 0.45
	for _, side in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Roof"
		wedge.Anchored = true
		wedge.Size = Vector3.new(depth + 1, roofHeight, width / 2 + 0.5)
		-- A wedge's tall face is its local +Z; turn each half so the tall
		-- faces meet in the middle and form the ridge.
		wedge.CFrame = CFrame.new(base + Vector3.new(side * width / 4, height + roofHeight / 2, 0))
			* CFrame.Angles(0, math.rad(-90 * side), 0)
		wedge.Color = roofColor
		wedge.Material = Enum.Material.Slate
		wedge.Parent = model
	end
	model.Parent = parent
end

local function tower(parent: Instance, base: Vector3, height: number)
	local model = Instance.new("Model")
	model.Name = "Tower"
	part({
		Name = "Shaft",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 14, 14),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 190, 170),
		Material = Enum.Material.Cobblestone,
		Parent = model,
	})
	part({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 17, 17),
		CFrame = CFrame.new(base + Vector3.new(0, height + 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 70, 60),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	model.Parent = parent
end

local function giantTree(parent: Instance, base: Vector3, height: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "GiantTree"
	local trunkWidth = height * 0.1
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, trunkWidth, trunkWidth),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(110, 78, 52),
		Material = Enum.Material.Wood,
		Parent = model,
	})
	for i = 1, 3 do
		local size = height * rng:NextNumber(0.28, 0.4)
		part({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.8, size),
			Position = base + Vector3.new(rng:NextNumber(-8, 8), height * (0.75 + i * 0.08), rng:NextNumber(-8, 8)),
			Color = Color3.fromRGB(70 + rng:NextInteger(0, 30), 140 + rng:NextInteger(0, 30), 70),
			Material = Enum.Material.Grass,
			Parent = model,
		})
	end
	model.Parent = parent
end

local function supplyStation(parent: Instance, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "SupplyStation"
	local crate = part({
		Name = "Crate",
		Size = Vector3.new(6, 5, 6),
		Position = position + Vector3.new(0, 2.5, 0),
		Color = Color3.fromRGB(150, 110, 60),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	part({
		Name = "Canisters",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 2.2, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(180, 190, 200),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local beacon = part({
		Name = "Beacon",
		Size = Vector3.new(1, 30, 1),
		Position = position + Vector3.new(0, 20, 0),
		Color = Color3.fromRGB(120, 230, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = beacon.Color
	light.Range = 18
	light.Parent = beacon
	CollectionService:AddTag(crate, Config.Tags.Supply)
	model.Parent = parent
end

-- Returns spawn points for giants (just inside the walls, spread out).
function MapBuilder.Build(): { Vector3 }
	local existing = Workspace:FindFirstChild("GiantHuntersMap")
	if existing then
		existing:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "GiantHuntersMap"
	map.Parent = Workspace

	local rng = Random.new(1845)
	local half = Config.World.HalfSize
	local wallHeight = Config.World.WallHeight
	local thickness = Config.World.WallThickness

	-- Ground: grass beyond the walls, cobbled streets inside.
	part({
		Name = "Meadow",
		Size = Vector3.new(half * 5, 2, half * 5),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(104, 168, 84),
		Material = Enum.Material.Grass,
		Parent = map,
	})
	part({
		Name = "Streets",
		Size = Vector3.new(half * 2, 0.2, half * 2),
		Position = Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(190, 180, 160),
		Material = Enum.Material.Cobblestone,
		Parent = map,
	})

	-- The great wall, with a walkway on top and crenellations.
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx, sz = side[1], side[2]
		local length = half * 2 + thickness * 2
		local size = if sx ~= 0 then Vector3.new(thickness, wallHeight, length) else Vector3.new(length, wallHeight, thickness)
		local centre = Vector3.new(sx * (half + thickness / 2), wallHeight / 2, sz * (half + thickness / 2))
		part({
			Name = "Wall",
			Size = size,
			Position = centre,
			Color = Color3.fromRGB(196, 186, 168),
			Material = Enum.Material.Brick,
			Parent = map,
		})
		for i = -half, half, 16 do
			local along = if sx ~= 0 then Vector3.new(0, 0, i) else Vector3.new(i, 0, 0)
			part({
				Name = "Merlon",
				Size = Vector3.new(4, 4, 4),
				Position = Vector3.new(centre.X, wallHeight + 2, centre.Z) + along,
				Color = Color3.fromRGB(186, 176, 158),
				Material = Enum.Material.Brick,
				CastShadow = false,
				Parent = map,
			})
		end
	end

	-- City blocks on a street grid. The east quarter is forest instead, and
	-- the middle is the open plaza.
	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = map
	local forest = Instance.new("Folder")
	forest.Name = "Forest"
	forest.Parent = map
	local spacing = Config.World.StreetSpacing
	for x = -half + spacing, half - spacing, spacing do
		for z = -half + spacing, half - spacing, spacing do
			local centre = Vector3.new(x, 0, z)
			local fromMiddle = math.max(math.abs(x), math.abs(z))
			if fromMiddle < spacing * 1.5 then
				continue -- plaza
			end
			if x > half * 0.35 then
				-- Forest: a couple of huge trees per block.
				for _ = 1, 2 do
					giantTree(forest, centre + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)), rng:NextNumber(70, 105), rng)
				end
			elseif rng:NextNumber() < 0.12 then
				tower(city, centre, rng:NextNumber(55, 85))
			else
				-- 2-4 houses per block, leaving the street clear.
				for _ = 1, rng:NextInteger(2, 4) do
					local offset = Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
					house(city, centre + offset, rng:NextNumber(12, 18), rng:NextNumber(12, 18), rng:NextNumber(18, 42), rng)
				end
			end
		end
	end

	-- Plaza: a fountain-less clock tower as the landmark and the spawn.
	tower(map, Vector3.new(0, 0, -30), 60)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HunterSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.Position = Vector3.new(0, 0.5, 20)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 3
	spawn.Parent = map

	-- Supply stations: plaza plus one per city quarter.
	supplyStation(map, Vector3.new(18, 0, 10))
	supplyStation(map, Vector3.new(-half * 0.6, 0, half * 0.6))
	supplyStation(map, Vector3.new(-half * 0.6, 0, -half * 0.6))
	supplyStation(map, Vector3.new(half * 0.25, 0, -half * 0.7))
	supplyStation(map, Vector3.new(half * 0.7, 0, half * 0.1))

	-- Giant entry points: spread just inside each wall.
	local spawns = {}
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		for _, t in { -0.5, 0, 0.5 } do
			local along = t * half * 1.6
			local inset = half - 30
			local p = if side[1] ~= 0
				then Vector3.new(side[1] * inset, 0, along)
				else Vector3.new(along, 0, side[2] * inset)
			table.insert(spawns, p)
		end
	end
	return spawns
end

return MapBuilder
