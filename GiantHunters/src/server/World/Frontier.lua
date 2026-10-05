--!strict
-- The far wilds: the old frontier beyond the district's roads, where the
-- first settlers lived before the Great Wall went up (Layout says where;
-- World/Ground raises and digs the terrain):
--
--   * The old outer wall: a broken ring of an older, lower wall (64 studs)
--     at the foot of the hills. Standing stretches with a few towers,
--     broken stubs, whole sections toppled flat into the grass, gaps where
--     the road and the river pass, moss and bushes everywhere. A ruined
--     gatehouse stands astride the south road, a crate on its tall tower.
--   * Needle Rock Gorge (south-south-west): a ravine between two rock
--     ridges, crossed by rope bridges, and tall stone spires round it.
--   * Misty Lake (south-south-east): an island with a broken tower and a
--     little shrine, a pier with a rowboat, reeds, lily pads, drifting mist.
--   * The Elder Tree (north): a colossal tree, 320 studs tall, with
--     platforms spiralling up its trunk, rope bridges out to three
--     neighbours, and a crate in a lookout hidden in its crown.
--   * Wildflowers in the meadows and fallen logs on the plains.
--
-- Wilds builds this early (after the landmarks), passing in its spacing,
-- hook-coverage and point-of-interest helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)
local Landmarks = require(script.Parent.Landmarks)
local Layout = require(script.Parent.Layout)

local Frontier = {}

type Helpers = Landmarks.Helpers

local P = Kit.Palette
local OLD_STONE = Color3.fromRGB(160, 154, 140)
local OLD_DARK = Color3.fromRGB(124, 120, 110)
local MOSS = Color3.fromRGB(92, 124, 70)
local PLANKS = Color3.fromRGB(140, 104, 66)
local ROPE = Color3.fromRGB(196, 170, 120)
local ROCKS = { Color3.fromRGB(150, 140, 128), Color3.fromRGB(164, 152, 136), Color3.fromRGB(136, 128, 120) }
local BUSH = Color3.fromRGB(82, 128, 62)

local function atomic(model: Model): Model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

-- A rope bridge from `a` to `b` (the ends of its deck): planks sagging in
-- the middle, a hand rope and posts on each side. Walk it or swing under it.
local function ropeBridge(parent: Instance, a: Vector3, b: Vector3, width: number)
	local model = atomic(Kit.Model("RopeBridge", parent))
	local span = (b - a).Magnitude
	local count = math.max(3, math.ceil(span / 9))
	local sag = span * 0.05
	local function at(t: number): Vector3
		return a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
	end
	for i = 1, count do
		local p0, p1 = at((i - 1) / count), at(i / count)
		Kit.Part({ Name = "Planks", Size = Vector3.new(width, 0.8, (p1 - p0).Magnitude + 0.3), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = model })
	end
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local side = Vector3.new(flat.Z, 0, -flat.X) * (width / 2)
	local up = Vector3.new(0, 3.4, 0)
	for _, s in { -1, 1 } do
		for _, half in { { 0, 0.5 }, { 0.5, 1 } } do
			Kit.Rod(model, "Rope", at(half[1]) + side * s + up, at(half[2]) + side * s + up, 0.35, ROPE, Enum.Material.Fabric, true)
		end
		for _, t in { 0, 1 } do
			Kit.Detail({ Name = "Post", Size = Vector3.new(0.7, 5, 0.7), Position = at(t) + side * s + Vector3.new(0, 1.8, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		end
	end
end

-- === The old outer wall ======================================================

local function outerWall(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "OldOuterWall"
	folder.Parent = parent
	local spec = Layout.OuterWall
	local R, thick, H = spec.Radius, spec.Thickness, spec.Height
	local count = math.floor(2 * math.pi * R / 46)
	local step = 2 * math.pi / count
	local length = 2 * R * math.tan(step / 2) + 0.5
	local gateCentre = Vector3.new(Layout.RoadX(R), 0, R)
	for i = 0, count - 1 do
		local angle = i * step
		local centre = Geo.Polar(angle, R)
		-- local X runs along the wall, +Z faces out
		local base = CFrame.new(centre) * CFrame.Angles(0, angle, 0)
		local gap = (centre - gateCentre).Magnitude < 58 -- the gatehouse
			or Layout.DistanceToRoads(centre) < Layout.RoadHalfWidth + 24
			or Geo.InRiver(centre.X, centre.Z, 34)
		-- Long runs standing, runs broken down, runs gone.
		local state = math.noise(i * 46 / 230, 0.37, 9.1) + rng:NextNumber(-0.12, 0.12)
		if not gap and state > 0.06 then
			local height = H + rng:NextNumber(-5, 4)
			Kit.Part({ Name = "OldWall", Size = Vector3.new(length, height, thick), CFrame = base * CFrame.new(0, height / 2, 0), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
			-- One merlon a section (most have fallen), on the outer edge.
			if rng:NextNumber() < 0.7 then
				Kit.Part({ Name = "Merlon", Size = Vector3.new(6, 4, 2.6), CFrame = base * CFrame.new(rng:NextNumber(-0.3, 0.3) * length, height + 2, thick / 2 - 1.3), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
			end
			if i % 9 == 0 then
				local tower = height + 14
				Kit.Part({ Name = "WallTower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(tower, 22, 22), CFrame = base * CFrame.new(0, tower / 2, 2) * Kit.UPRIGHT, Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
				Kit.Part({ Name = "TowerTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 25, 25), CFrame = base * CFrame.new(0, tower + 1.5, 2) * Kit.UPRIGHT, Color = OLD_DARK, Material = Enum.Material.Slate, Parent = folder })
			end
			h.AddAnchor(centre)
		elseif not gap and state > -0.24 then
			-- Broken down to a stub with a slanting top.
			local height = rng:NextNumber(12, 34)
			Kit.Part({ Name = "OldWall", Size = Vector3.new(length, height, thick), CFrame = base * CFrame.new(0, height / 2, 0), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
			local jag = rng:NextNumber(6, 16)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			Kit.Part({ Class = "WedgePart", Name = "BrokenTop", Size = Vector3.new(thick, jag, length * 0.5), CFrame = base * CFrame.new(side * length / 4, height + jag / 2, 0) * CFrame.Angles(0, side * math.pi / 2, 0), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
			local out = if rng:NextNumber() < 0.6 then 1 else -1
			Kit.Part({ Name = "Rubble", Size = Vector3.new(rng:NextNumber(6, 10), rng:NextNumber(4, 7), rng:NextNumber(5, 8)), CFrame = base * CFrame.new(rng:NextNumber(-0.4, 0.4) * length, 2, out * (thick / 2 + 6)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = OLD_DARK, Material = Enum.Material.Slate, Parent = folder })
		elseif not gap then
			if rng:NextNumber() < 0.55 then
				-- Toppled whole: the section lies flat where it fell.
				local fell = rng:NextNumber(26, 40)
				local out = if rng:NextNumber() < 0.7 then 1 else -1
				Kit.Part({ Name = "Toppled", Size = Vector3.new(length * 0.85, thick * 0.9, fell), CFrame = base * CFrame.new(0, thick * 0.38, out * (fell / 2 + 2)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.05, 0.05)), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = folder })
			end
			Kit.Part({ Name = "Rubble", Size = Vector3.new(rng:NextNumber(7, 12), rng:NextNumber(4, 8), rng:NextNumber(6, 9)), CFrame = base * CFrame.new(rng:NextNumber(-0.3, 0.3) * length, 2.5, 0) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = OLD_DARK, Material = Enum.Material.Slate, Parent = folder })
		end
		-- Overgrown: moss up the inner face, bushes at the foot.
		if not gap and state > -0.24 and rng:NextNumber() < 0.3 then
			Kit.Detail({ Name = "Moss", Size = Vector3.new(rng:NextNumber(8, 16), rng:NextNumber(10, 24), 0.6), CFrame = base * CFrame.new(rng:NextNumber(-0.3, 0.3) * length, 6, -thick / 2 - 0.2), Color = MOSS, Material = Enum.Material.Grass, Parent = folder })
		end
		if not gap and i % 3 == 1 then
			local size = rng:NextNumber(8, 15)
			Kit.Part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = (base * CFrame.new(rng:NextNumber(-0.5, 0.5) * length, size * 0.25, -thick / 2 - size * 0.3)).Position, Color = BUSH, Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = folder })
		end
		if not gap then
			h.Occupy(centre, length / 2 + 4)
		end
	end

	-- The gatehouse on the south road: two towers either side of the road,
	-- the arch long fallen. The west tower still stands (a crate on top);
	-- the east one has crumbled to half its height.
	local model = atomic(Kit.Model("OldGatehouse", parent))
	local gate = CFrame.new(h.Grounded(gateCentre)) -- local X across the road, +Z out
	local towerWidth, half = 20, 13 + 10
	local tall, short = 86, 46
	for _, side in { -1, 1 } do
		local height = if side < 0 then tall else short
		local tower = gate * CFrame.new(side * half, 0, 0)
		Kit.Part({ Name = "GateTower", Size = Vector3.new(towerWidth, height, towerWidth + 4), CFrame = tower * CFrame.new(0, height / 2, 0), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
		Kit.Part({ Name = "Plinth", Size = Vector3.new(towerWidth + 3, 6, towerWidth + 7), CFrame = tower * CFrame.new(0, 3, 0), Color = OLD_DARK, Material = Enum.Material.Cobblestone, Parent = model })
		Kit.Detail({ Name = "Moss", Size = Vector3.new(10, height * 0.5, 0.6), CFrame = tower * CFrame.new(-side * 2, height * 0.3, -(towerWidth + 4) / 2 - 0.2), Color = MOSS, Material = Enum.Material.Grass, Parent = model })
		Kit.Detail({ Name = "Window", Size = Vector3.new(2.6, 5, 0.6), CFrame = tower * CFrame.new(0, height * 0.6, -(towerWidth + 4) / 2 - 0.1), Color = Color3.fromRGB(40, 34, 30), Parent = model })
	end
	-- The tall tower's broken crown round a flat top; the arch's springer
	-- still juts out over the road from it, iron bars of the old portcullis
	-- hanging below.
	local west = gate * CFrame.new(-half, tall, 0)
	for k, rise in { 7, 3, 9, 5 } do
		local turn = CFrame.Angles(0, k * math.pi / 2, 0)
		Kit.Part({ Name = "BrokenCrown", Size = Vector3.new(towerWidth * 0.4, rise, 2.4), CFrame = west * turn * CFrame.new(-towerWidth * 0.25, rise / 2, -(towerWidth / 2 + 0.8)), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
	end
	h.Supplies(model, (west * CFrame.new(0, 0, 2)).Position, true)
	local springer = gate * CFrame.new(-half + towerWidth / 2 + 5, 52, 0)
	Kit.Part({ Name = "ArchSpringer", Size = Vector3.new(10, 7, 14), CFrame = springer, Color = OLD_DARK, Material = Enum.Material.Slate, Parent = model })
	for _, x in { -3, 0, 3 } do
		local top = springer * CFrame.new(x, -3.5, 0)
		Kit.Rod(model, "PortcullisBar", top.Position, (top * CFrame.new(0, -9 - math.abs(x) * 2, 0)).Position, 0.6, P.Iron, Enum.Material.Metal, true)
	end
	-- The fallen arch and the east tower's top, lying beside the road.
	Kit.Part({ Name = "FallenArch", Size = Vector3.new(30, 7, 12), CFrame = gate * CFrame.new(half + 4, 3, -24) * CFrame.Angles(0.05, 0.35, 0.1), Color = OLD_DARK, Material = Enum.Material.Slate, Parent = model })
	for k = 1, 4 do
		Kit.Part({ Name = "Rubble", Size = Vector3.new(5 + k % 3 * 2, 4 + k % 2 * 2, 6), CFrame = gate * CFrame.new(half + 8 + k * 3, 2, 12 + k * 4) * CFrame.Angles(0.3 * k, 0.7 * k, 0.2), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
	end
	h.AddAnchor(gateCentre)
	h.Occupy(gateCentre + Vector3.new(-half, 0, 0), towerWidth)
	h.Occupy(gateCentre + Vector3.new(half, 0, 0), towerWidth)
	h.Poi("OuterWall", "Old Outer Wall", gateCentre, 80)
end

-- === Needle Rock Gorge =======================================================

-- A stone spire: three blocks of layered rock stacked and twisted, a tuft
-- of green on some tops.
local function spire(parent: Instance, at: Vector3, height: number, width: number, rng: Random): Vector3
	local model = atomic(Kit.Model("RockSpire", parent))
	local frame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local y = 0
	for k, share in { 0.5, 0.32, 0.22 } do
		local tall = height * share + 4
		local w = width * (1 - (k - 1) * 0.28)
		frame = frame * CFrame.Angles(rng:NextNumber(-0.04, 0.04), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.04, 0.04))
		Kit.Part({ Name = "Spire", Size = Vector3.new(w, tall, w * rng:NextNumber(0.75, 0.95)), CFrame = frame * CFrame.new(0, y + tall / 2, 0), Color = ROCKS[k], Material = Enum.Material.Rock, Parent = model })
		y += tall - 4
	end
	local top = (frame * CFrame.new(0, y + 4, 0)).Position
	if rng:NextNumber() < 0.45 then
		Kit.Part({ Name = "Tuft", Shape = Enum.PartType.Ball, Size = Vector3.one * width * 0.6, Position = top + Vector3.new(0, 1, 0), Color = BUSH, Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
	end
	return top
end

local function gorge(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "NeedleRockGorge"
	folder.Parent = parent
	local along, across = Layout.GorgeAlong, Layout.GorgeAcross
	local run = Layout.GorgeRun
	-- Spires (the tallest two carry crates).
	local order = table.clone(Layout.GorgeSpires)
	table.sort(order, function(a, b)
		return a.Height > b.Height
	end)
	for k, s in order do
		local base = h.Grounded(s.At, 2)
		local top = spire(folder, base, s.Height, s.Width, rng)
		if k <= 2 then
			h.Supplies(folder, top, true)
		end
		h.AddAnchor(s.At)
		h.Occupy(s.At, s.Width * 0.8)
	end
	-- The ridges count as something to hook (rock 50-90 studs up).
	for _, ridge in Layout.GorgeRidges do
		if ridge.Centre.Y + ridge.Radius >= 40 then
			h.AddAnchor(ridge.Centre)
		end
		h.Occupy(ridge.Centre, ridge.Radius * 0.8)
	end
	-- Rope bridges across the ravine, from the first ledge 46 studs up on
	-- each side.
	local function ledge(at: Vector3, side: number): Vector3?
		for lateral = 10, 80, 2 do
			local p = at + across * side * lateral
			local height = Layout.GroundHeight(p.X, p.Z)
			if height >= 46 then
				return Vector3.new(p.X, height - 0.5, p.Z)
			end
		end
		return nil
	end
	local bridges = 0
	for _, t in { 0.3, 0.7, 0.4, 0.6, 0.22, 0.78 } do
		local mid = along * (run.From + (run.To - run.From) * t)
		local a, b = ledge(mid, -1), ledge(mid, 1)
		if a and b and bridges < 2 and (bridges == 0 or t > 0.5) then
			bridges += 1
			ropeBridge(folder, a, b, 6)
		end
	end
	-- Boulders on the ravine floor, and a crate halfway along it.
	for k = 1, 5 do
		local p = along * (run.From + (run.To - run.From) * (k - 0.5) / 5) + across * rng:NextNumber(-10, 10)
		local size = rng:NextNumber(5, 9)
		Kit.Part({ Name = "Boulder", Size = Vector3.new(size * 1.3, size, size), CFrame = CFrame.new(p + Vector3.new(0, size * 0.3, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = ROCKS[rng:NextInteger(1, #ROCKS)], Material = Enum.Material.Rock, Parent = folder })
	end
	h.Supplies(folder, along * ((run.From + run.To) / 2) + across * 4, true)
	h.Poi("Gorge", "Needle Rock Gorge", along * ((Layout.Gorge.Inner + Layout.Gorge.Outer) / 2), 170)
end

-- === Misty Lake ==============================================================

local function lake(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "MistyLake"
	folder.Parent = parent
	local spec = Layout.Lake
	for _, circle in spec.Circles do
		h.Occupy(circle.Centre, circle.Radius)
	end

	-- The island: a broken round tower (a crate on its floor) and a small
	-- shrine with a lantern.
	local isle = h.Grounded(spec.Island, 2)
	local model = atomic(Kit.Model("IsleTower", folder))
	local towards = Geo.Flat(-spec.Centre).Unit -- toward the town
	local base = CFrame.lookAt(isle, isle + towards)
	local height, width = 62, 16
	local tower = base * CFrame.new(6, 0, 4)
	Kit.Part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, width, width), CFrame = tower * CFrame.new(0, height / 2, 0) * Kit.UPRIGHT, Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
	for i, rise in { 8, 3, 11, 5 } do
		Kit.Part({ Name = "BrokenWall", Size = Vector3.new(6, rise, 2.6), CFrame = tower * CFrame.Angles(0, i / 4 * math.pi * 2, 0) * CFrame.new(0, height + rise / 2, -width / 2 + 1.3), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
	end
	Kit.Part({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, width - 2, width - 2), CFrame = tower * CFrame.new(0, height + 0.5, 0) * Kit.UPRIGHT, Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = model })
	h.Supplies(model, (tower * CFrame.new(0, height + 1, 0)).Position, true)
	Kit.Detail({ Name = "Moss", Size = Vector3.new(7, 22, 1), CFrame = tower * CFrame.Angles(0, 2.4, 0) * CFrame.new(0, 11, -width / 2 - 0.1), Color = MOSS, Material = Enum.Material.Grass, Parent = model })
	for _, y in { 18, 36, 50 } do
		Kit.Detail({ Name = "Window", Size = Vector3.new(2.2, 4.4, 0.6), CFrame = tower * CFrame.Angles(0, y * 0.07, 0) * CFrame.new(0, y, -width / 2 - 0.05), Color = Color3.fromRGB(40, 34, 30), Parent = model })
	end
	local shrine = base * CFrame.new(-8, 0, -8)
	Kit.Part({ Name = "ShrineStep", Size = Vector3.new(10, 1.6, 8), CFrame = shrine * CFrame.new(0, 0.8, 0), Color = OLD_DARK, Material = Enum.Material.Cobblestone, Parent = model })
	for _, x in { -3.6, 3.6 } do
		Kit.Part({ Name = "ShrinePillar", Size = Vector3.new(1.4, 8, 1.4), CFrame = shrine * CFrame.new(x, 5.6, 0), Color = OLD_STONE, Material = Enum.Material.Slate, Parent = model })
	end
	Kit.Part({ Name = "ShrineRoof", Size = Vector3.new(10, 1.4, 5), CFrame = shrine * CFrame.new(0, 10.3, 0), Color = OLD_DARK, Material = Enum.Material.Slate, Parent = model })
	Kit.Torch(model, shrine * CFrame.new(0, 1.6, 0))
	h.AddAnchor(isle)

	-- The pier, from the shore toward the island, and a rowboat tied to it.
	local main = spec.Circles[1]
	local shore = main.Centre + towards * main.Radius
	local pierFrom, pierTo = shore + towards * 8, shore - towards * 38
	local pier = atomic(Kit.Model("Pier", folder))
	local pierLength = (pierTo - pierFrom).Magnitude
	local deck = CFrame.lookAt((pierFrom + pierTo) / 2 + Vector3.new(0, 1.4, 0), pierTo + Vector3.new(0, 1.4, 0))
	Kit.Part({ Name = "Deck", Size = Vector3.new(7, 0.8, pierLength), CFrame = deck, Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = pier })
	for k = 0, 4 do
		for _, x in { -3, 3 } do
			Kit.Detail({ Name = "Post", Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 1, 1), CFrame = deck * CFrame.new(x, -4, -pierLength / 2 + 4 + k * (pierLength - 8) / 4) * Kit.UPRIGHT, Color = P.Timber, Material = Enum.Material.Wood, Parent = pier })
		end
	end
	local boat = deck * CFrame.new(7, -2.2, -pierLength / 2 + 8) * CFrame.Angles(0, 0.15, 0)
	Kit.Part({ Name = "Hull", Size = Vector3.new(4.4, 1.6, 9), CFrame = boat, Color = Color3.fromRGB(122, 84, 54), Material = Enum.Material.WoodPlanks, Parent = pier })
	Kit.Part({ Class = "WedgePart", Name = "Bow", Size = Vector3.new(4.4, 1.6, 3), CFrame = boat * CFrame.new(0, 0, -6) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(122, 84, 54), Material = Enum.Material.WoodPlanks, Parent = pier })
	h.Occupy(shore, 10)

	-- Reeds round the shores and lily pads on the water.
	local reedGreens = { Color3.fromRGB(110, 140, 70), Color3.fromRGB(132, 150, 82), Color3.fromRGB(96, 124, 64) }
	local placed = 0
	for _ = 1, 120 do
		if placed >= 24 then
			break
		end
		local circle = spec.Circles[rng:NextInteger(1, #spec.Circles)]
		local p = circle.Centre + Geo.Polar(rng:NextNumber(0, math.pi * 2), circle.Radius - rng:NextNumber(1, 5))
		-- On an outer edge (not inside a neighbouring bay) and off the pier.
		if not Layout.InWater(p, -8) and (p - shore).Magnitude > 16 then
			placed += 1
			for k = 1, 3 do
				local tall = rng:NextNumber(5, 8)
				local spot = p + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
				Kit.Detail({ Name = "Reed", Size = Vector3.new(0.5, tall, 0.5), CFrame = CFrame.new(spot + Vector3.new(0, tall / 2 - 2, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color = reedGreens[k], Material = Enum.Material.Grass, CanCollide = false, Parent = folder })
			end
		end
	end
	for _ = 1, 12 do
		local circle = spec.Circles[rng:NextInteger(1, #spec.Circles)]
		local p = circle.Centre + Geo.Polar(rng:NextNumber(0, math.pi * 2), circle.Radius * rng:NextNumber(0.3, 0.85))
		if (p - isle).Magnitude > 34 then
			local size = rng:NextNumber(3, 5)
			Kit.Detail({ Name = "LilyPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, size, size), CFrame = CFrame.new(p.X, -1.85, p.Z) * Kit.UPRIGHT, Color = Color3.fromRGB(86, 140, 70), Material = Enum.Material.Grass, CanCollide = false, Parent = folder })
		end
	end

	-- Mist drifting low over the water (no texture: soft default puffs).
	for _, circle in spec.Circles do
		local emitterPart = Kit.Part({ Name = "Mist", Size = Vector3.new(circle.Radius * 1.4, 1, circle.Radius * 1.4), Position = Vector3.new(circle.Centre.X, 1, circle.Centre.Z), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false, Parent = folder })
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "Mist"
		mist.Color = ColorSequence.new(Color3.fromRGB(232, 238, 242))
		mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 22) })
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) })
		mist.Lifetime = NumberRange.new(8, 12)
		mist.Speed = NumberRange.new(0.5, 1.5)
		mist.SpreadAngle = Vector2.new(80, 80)
		mist.Rate = circle.Radius / 40
		mist.LightInfluence = 0.6
		mist.EmissionDirection = Enum.NormalId.Top
		mist.Parent = emitterPart
	end
	h.Poi("MistLake", "Misty Lake", spec.Centre, 150)
end

-- === The Elder Tree ==========================================================

local ELDER_HEIGHT = 320

-- A deck round a neighbour's trunk where a rope bridge lands.
local function landing(parent: Instance, base: Vector3, trunk: number, y: number)
	local size = trunk + 16
	local deck = CFrame.new(base + Vector3.new(0, y, 0))
	Kit.Part({ Name = "Deck", Size = Vector3.new(size, 1.2, size), CFrame = deck, Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = parent })
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, 1) } do
		Kit.Rod(parent, "Strut", (deck * CFrame.new(corner * (size / 2 - 1) - Vector3.new(0, 0.6, 0))).Position, base + Vector3.new(0, y - size * 0.45, 0), 0.8, P.Timber, Enum.Material.Wood, true)
	end
end

local function elderTree(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "ElderTree"
	folder.Parent = parent
	local base = h.Grounded(Layout.ElderTree, 4)
	local model = atomic(Kit.Model("ElderTree", folder))
	local H = ELDER_HEIGHT
	local lowerWidth, upperWidth, split = 38, 27, 180
	local function trunkRadius(y: number): number
		return (if y < split then lowerWidth else upperWidth) / 2
	end
	Kit.Part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(split + 10, lowerWidth, lowerWidth), CFrame = CFrame.new(base + Vector3.new(0, (split + 10) / 2, 0)) * Kit.UPRIGHT, Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	Kit.Part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(H - split, upperWidth, upperWidth), CFrame = CFrame.new(base + Vector3.new(0, split + (H - split) / 2, 0)) * Kit.UPRIGHT, Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	-- Great roots spreading over the mound.
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Geo.Polar(angle, 1)
		local foot = base + out * lowerWidth * 0.75 + Vector3.new(0, 18, 0)
		Kit.Part({ Class = "WedgePart", Name = "Root", Size = Vector3.new(11, 40, 36), CFrame = CFrame.lookAt(foot, foot + out), Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	end
	-- Platforms spiralling up the trunk, each with a rail and a strut.
	type Pad = { Angle: number, Y: number, Edge: number }
	local pads: { Pad } = {}
	for k = 0, 7 do
		local angle = k * 1.1
		local y = 36 + k * 30
		local radius = trunkRadius(y)
		local frame = CFrame.new(base + Geo.Polar(angle, radius + 7, y)) * CFrame.Angles(0, angle, 0)
		Kit.Part({ Name = "Platform", Size = Vector3.new(18, 1.2, 16), CFrame = frame, Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = model })
		Kit.Detail({ Name = "Rail", Size = Vector3.new(18, 0.5, 0.5), CFrame = frame * CFrame.new(0, 3, 7.8), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		Kit.Rod(model, "Strut", (frame * CFrame.new(0, -0.6, 7)).Position, base + Vector3.new(0, y - 14, 0), 0.9, P.Timber, Enum.Material.Wood, true)
		table.insert(pads, { Angle = angle, Y = y, Edge = radius + 15 })
	end
	-- Thick branches, each ending in a leafy cluster, and the crown.
	for b = 1, 6 do
		local angle = b / 6 * math.pi * 2 + 0.5 + rng:NextNumber(-0.3, 0.3)
		local y = H * rng:NextNumber(0.5, 0.82)
		local length = rng:NextNumber(60, 90)
		local start = base + Vector3.new(0, y, 0)
		local tip = start + Geo.Polar(angle, length) + Vector3.new(0, length * rng:NextNumber(0.2, 0.45), 0)
		Kit.Rod(model, "Branch", start, tip, rng:NextNumber(7, 9), P.Bark, Enum.Material.Wood)
		Kit.Part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(44, 58), Position = tip + Vector3.new(0, 8, 0), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
	end
	for i, size in { 130, 104, 84 } do
		local offset = Geo.Polar(i * 2.1, if i == 1 then 0 else 30)
		Kit.Part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = base + offset + Vector3.new(0, H - 10 + i * 12, 0), Color = P.Leaves[i], Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	-- The lookout hidden in the crown: a deck round the trunk, rails, a
	-- crate and a lantern.
	local nestY = 270
	local nest = CFrame.new(base + Vector3.new(0, nestY, 0))
	local nestSize = 40
	Kit.Part({ Name = "Lookout", Size = Vector3.new(nestSize, 1.4, nestSize), CFrame = nest, Color = PLANKS, Material = Enum.Material.WoodPlanks, Parent = model })
	for i = 0, 3 do
		Kit.Detail({ Name = "Rail", Size = Vector3.new(nestSize, 0.5, 0.5), CFrame = nest * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 3.2, -nestSize / 2 + 0.3), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	h.Supplies(model, (nest * CFrame.new(upperWidth / 2 + 6, 0.7, 0)).Position, true)
	Kit.Torch(model, nest * CFrame.new(-nestSize / 2 + 2, 0.7, nestSize / 2 - 2))
	h.AddAnchor(base)
	h.Occupy(base, 44)

	-- Three neighbours, each joined to a platform by a rope bridge.
	for _, k in { 2, 4, 6 } do
		local pad = pads[k]
		local spot = Layout.ElderTree + Geo.Polar(pad.Angle, 118)
		if h.ClearSpot(spot, 14) and h.Free(spot, 12) then
			local ground = h.Grounded(spot, 3)
			local deckY = base.Y + pad.Y - ground.Y
			local _, trunk = h.GiantTree(folder, ground, math.max(150, deckY + 70), rng, deckY)
			landing(folder, ground, trunk, deckY)
			local from = base + Geo.Polar(pad.Angle, pad.Edge - 1, pad.Y + 0.4)
			local to = ground + Geo.Polar(pad.Angle + math.pi, (trunk + 16) / 2 - 1, deckY + 0.4)
			ropeBridge(folder, from, to, 5)
		end
	end
	h.Poi("ElderTree", "The Elder Tree", Layout.ElderTree, 130)
end

-- === Meadows and the plains ==================================================

local FLOWERS = {
	Color3.fromRGB(250, 220, 90), -- buttercups
	Color3.fromRGB(246, 244, 236), -- daisies
	Color3.fromRGB(176, 150, 226), -- lavender
	Color3.fromRGB(240, 150, 186), -- clover pink
	Color3.fromRGB(236, 110, 80), -- poppies
	Color3.fromRGB(120, 160, 236), -- cornflowers
}

local function wildflowers(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Wildflowers"
	folder.Parent = parent
	local placed = 0
	for _ = 1, 900 do
		if placed >= 40 then
			break
		end
		local p = Geo.Polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(400, Layout.OuterWall.Radius - 40))
		if Layout.Meadow(p.X, p.Z) > 0.36 and Layout.OpenPlain(p, 4) and h.ClearSpot(p, 4) and h.Free(p, 4) then
			placed += 1
			local main = FLOWERS[rng:NextInteger(1, #FLOWERS)]
			local other = FLOWERS[rng:NextInteger(1, #FLOWERS)]
			for k = 1, 3 do
				local size = if k == 1 then rng:NextNumber(9, 14) else rng:NextNumber(4, 7)
				local spot = if k == 1 then p else p + Geo.Polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, 10))
				Kit.Detail({ Name = "Flowers", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, size, size), CFrame = CFrame.new(spot.X, 0.25, spot.Z) * Kit.UPRIGHT, Color = if k == 2 then other else main, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = folder })
			end
		end
	end
end

local function fallenLogs(parent: Instance, h: Helpers, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "FallenLogs"
	folder.Parent = parent
	local placed = 0
	for _ = 1, 400 do
		if placed >= 16 then
			break
		end
		local p = Geo.Polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(420, Layout.OuterWall.Radius - 60))
		local length = rng:NextNumber(26, 44)
		if Layout.OpenPlain(p, 10) and h.ClearSpot(p, 12) and h.Free(p, length / 2 + 4) then
			placed += 1
			local model = atomic(Kit.Model("FallenLog", folder))
			local width = rng:NextNumber(4.5, 6.5)
			local frame = CFrame.new(h.Grounded(p) + Vector3.new(0, width / 2 - 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			Kit.Part({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, width, width), CFrame = frame, Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
			Kit.Detail({ Name = "Moss", Size = Vector3.new(length * 0.4, 0.4, width * 0.6), CFrame = frame * CFrame.new(rng:NextNumber(-0.2, 0.2) * length, width / 2, 0), Color = MOSS, Material = Enum.Material.Grass, Parent = model })
			h.Occupy(p, length / 2)
		end
	end
end

function Frontier.Build(parent: Instance, rng: Random, helpers: Helpers)
	local folder = Instance.new("Folder")
	folder.Name = "FarWilds"
	folder.Parent = parent
	outerWall(folder, helpers, rng)
	gorge(folder, helpers, rng)
	lake(folder, helpers, rng)
	elderTree(folder, helpers, rng)
end

-- After the forests, groves and towers: flowers and logs in what's left.
function Frontier.Dress(parent: Instance, rng: Random, helpers: Helpers)
	local folder = Instance.new("Folder")
	folder.Name = "Meadows"
	folder.Parent = parent
	wildflowers(folder, helpers, rng)
	fallenLogs(folder, helpers, rng)
end

return Frontier
