--!strict
-- Outside the wall: the land the giants walk in from.
--
--   * The forest of giant trees (south-east): trunks as wide as houses,
--     root buttresses, thick branches you can stand on, a hunters' platform
--     with a supply crate built round one of the trunks.
--   * Farms (south-west): cottages, a red barn, a windmill whose sails turn
--     (spun on each client), haystacks in the wheat.
--   * The road from the gate, fenced, with a signpost and an old cart.
--   * Lone trees and boulders on the plains, firs along the hills.
--   * Something to hook everywhere: groves, signal towers along the roads
--     and in a ring round the outer plains, and a last pass that puts a
--     lone giant tree in any stretch still too far from an anchor.
--   * The edge of the world: an invisible wall inside the hill ring.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local Wilds = {}

local W = Config.World
local P = Kit.Palette
local WALL_OUT = W.WallRadius + W.WallThickness

-- What's been put down so far, for spacing and hook coverage. Reset by
-- Wilds.Build.
type Footprint = { At: Vector3, Radius: number }
local footprints: { Footprint } = {} -- everything solid on the ground
local anchors: { Vector3 } = {} -- things 40+ studs tall to hook
local crates: { Vector3 } = {} -- supply crates outside the wall

local function occupy(p: Vector3, radius: number)
	table.insert(footprints, { At = Geo.Flat(p), Radius = radius })
end

local function free(p: Vector3, radius: number): boolean
	local flat = Geo.Flat(p)
	for _, f in footprints do
		if (f.At - flat).Magnitude < f.Radius + radius then
			return false
		end
	end
	return true
end

local function addAnchor(p: Vector3)
	table.insert(anchors, Geo.Flat(p))
end

-- Flat distance to the nearest hook anchor (the wall counts).
local function anchorDistance(p: Vector3): number
	local flat = Geo.Flat(p)
	local best = Geo.RadiusOf(flat) - WALL_OUT
	for _, a in anchors do
		best = math.min(best, (a - flat).Magnitude)
	end
	return best
end

local function crateDistance(p: Vector3): number
	local best = math.huge
	for _, c in crates do
		best = math.min(best, (c - Geo.Flat(p)).Magnitude)
	end
	return best
end

local function supplies(parent: Instance, p: Vector3, beam: boolean)
	Kit.SupplyStation(parent, p, beam)
	table.insert(crates, Geo.Flat(p))
end

-- `p` lifted onto the ground (hills, the castle hill), sunk `sink` studs.
local function grounded(p: Vector3, sink: number?): Vector3
	local height = Layout.GroundHeight(p.X, p.Z)
	return Vector3.new(p.X, if height > 0 then height - (sink or 0) else 0, p.Z)
end

local function clearSpot(p: Vector3, margin: number): boolean
	return Layout.DistanceToRoads(p) >= Layout.RoadHalfWidth + margin
		and not Geo.InRiver(p.X, p.Z, margin)
		and not Geo.InCastleHill(p, margin)
		and Geo.RadiusOf(p) > WALL_OUT + margin
end

-- In a polar region, or within `margin` studs of it.
type Region = { Angle: number, Spread: number, Inner: number, Outer: number }
local function nearRegion(p: Vector3, region: Region, margin: number): boolean
	local r = Geo.RadiusOf(p)
	if r < region.Inner - margin or r > region.Outer + margin then
		return false
	end
	local off = math.abs(Geo.AngleDelta(region.Angle, Geo.AngleOf(p))) - region.Spread
	return off <= 0 or off * r < margin
end

-- Taken by a named place: the forests, the farms, the training grounds,
-- the castle hill.
local function busy(p: Vector3, margin: number): boolean
	return nearRegion(p, Layout.Forest, margin)
		or nearRegion(p, Layout.Farms, margin)
		or nearRegion(p, Layout.GreatForest, margin)
		or nearRegion(p, Layout.Training, margin)
		or Geo.InCastleHill(p, margin)
end

-- Random points in a polar region, at least `spacing` apart.
local function scatter(region: { Angle: number, Spread: number, Inner: number, Outer: number }, count: number, spacing: number, margin: number, rng: Random): { Vector3 }
	local points: { Vector3 } = {}
	for _ = 1, count * 30 do
		if #points >= count then
			break
		end
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner, region.Outer))
		local ok = clearSpot(p, margin) and free(p, margin)
		for _, other in points do
			if ok and (other - p).Magnitude < spacing then
				ok = false
			end
		end
		if ok then
			table.insert(points, p)
		end
	end
	return points
end

-- === The forest of giant trees ==============================================

-- A giant tree: trunk, root buttresses, three thick branches each ending in
-- a leafy cluster, and a two-ball crown. `deckY` (height above the base)
-- keeps the branches clear of a platform built round the trunk. Leaves and
-- crowns are hookable, but you fly through them.
local function giantTree(parent: Instance, base: Vector3, height: number, rng: Random, deckY: number?): (Model, number)
	local model = Kit.Model("GiantTree", parent)
	local trunk = height * 0.1
	Kit.Part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, trunk, trunk), CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * Kit.UPRIGHT, Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	-- Root buttresses: wedges sloping down and away from the trunk (a
	-- wedge's tall face is its local +Z, here turned toward the trunk).
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local out = Geo.Polar(angle, 1)
		local foot = base + out * trunk * 0.7 + Vector3.new(0, height * 0.06, 0)
		Kit.Part({ Class = "WedgePart", Name = "Root", Size = Vector3.new(trunk * 0.3, height * 0.12, trunk * 0.9), CFrame = CFrame.lookAt(foot, foot + out), Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	end
	-- Thick branches, each ending in a leafy cluster.
	for b = 1, 3 do
		local angle = b / 3 * math.pi * 2 + rng:NextNumber(-0.6, 0.6)
		local length = height * rng:NextNumber(0.18, 0.3)
		local rise = rng:NextNumber(0.12, 0.4)
		local y = height * rng:NextNumber(0.42, 0.8)
		if deckY then
			-- The whole branch (it rises toward its tip) stays 8 studs clear
			-- of the deck.
			local thick = trunk * 0.16
			local function clear(at: number): boolean
				return at + length * rise + thick < deckY - 8 or at - thick > deckY + 8
			end
			for _ = 1, 8 do
				if clear(y) then
					break
				end
				y = height * rng:NextNumber(0.42, 0.8)
			end
			if not clear(y) then
				y = deckY + 9 + thick
			end
		end
		local start = base + Vector3.new(0, y, 0)
		local tip = start + Geo.Polar(angle, length) + Vector3.new(0, length * rise, 0)
		Kit.Rod(model, "Branch", start, tip, trunk * 0.32, P.Bark, Enum.Material.Wood)
		Kit.Part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * height * rng:NextNumber(0.15, 0.22), Position = tip + Vector3.new(0, height * 0.03, 0), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
	end
	for i = 1, 2 do
		local size = height * rng:NextNumber(0.3, 0.38)
		Kit.Part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = base + Vector3.new(rng:NextNumber(-0.08, 0.08) * height, height * (0.9 + i * 0.07), rng:NextNumber(-0.08, 0.08) * height), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	addAnchor(base)
	occupy(base, trunk * 0.7)
	return model, trunk
end

-- A square wooden deck round a trunk, railings and a supply crate on it,
-- and (with `torch`) a torch on the deck.
local function treePlatform(parent: Instance, base: Vector3, trunk: number, y: number, torch: boolean?)
	local model = Kit.Model("TreePlatform", parent)
	local size = trunk + 18
	local deck = CFrame.new(base + Vector3.new(0, y, 0))
	Kit.Part({ Name = "Deck", Size = Vector3.new(size, 1.2, size), CFrame = deck, Color = Color3.fromRGB(140, 104, 66), Material = Enum.Material.WoodPlanks, Parent = model })
	for i = 0, 3 do
		local side = CFrame.Angles(0, i * math.pi / 2, 0)
		Kit.Detail({ Name = "Rail", Size = Vector3.new(size, 0.4, 0.4), CFrame = deck * side * CFrame.new(0, 3, -size / 2 + 0.2), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		Kit.Detail({ Name = "Post", Size = Vector3.new(0.5, 3, 0.5), CFrame = deck * side * CFrame.new(-size / 2 + 0.25, 1.5, -size / 2 + 0.25), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		-- Struts down to the trunk.
		local corner = (deck * side * CFrame.new(-size / 2 + 1, -0.6, -size / 2 + 1)).Position
		Kit.Rod(model, "Strut", corner, base + Vector3.new(0, y - size * 0.45, 0), 0.8, P.Timber, Enum.Material.Wood, true)
	end
	supplies(model, (deck * CFrame.new(trunk / 2 + 5, 0.6, 0)).Position, true)
	if torch then
		Kit.Torch(model, deck * CFrame.new(-size / 2 + 1.5, 0.6, size / 2 - 1.5))
	end
end

local function forest(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "GiantForest"
	folder.Parent = parent
	local spots = scatter(Layout.Forest, 30, 46, 14, rng)
	for i, p in spots do
		local height = rng:NextNumber(115, 160)
		local deckY = if i == 1 then height * 0.42 else nil
		local _, trunk = giantTree(folder, p, height, rng, deckY)
		if deckY then
			treePlatform(folder, p, trunk, deckY)
		end
	end
end

-- === Farms ===================================================================

local function cottage(parent: Instance, frame: CFrame, rng: Random)
	local model = Kit.Model("Cottage", parent)
	local width, depth, height = rng:NextNumber(14, 18), rng:NextNumber(11, 14), rng:NextNumber(10, 13)
	Kit.Part({ Name = "Body", Size = Vector3.new(width, height, depth), CFrame = frame * CFrame.new(0, height / 2, 0), Color = P.Plaster[rng:NextInteger(1, #P.Plaster)], Material = Enum.Material.Plaster, Parent = model })
	Kit.Detail({ Name = "Door", Size = Vector3.new(3, 6, 0.4), CFrame = frame * CFrame.new(-width / 4, 3, -depth / 2 - 0.1), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	Kit.Detail({ Name = "Window", Size = Vector3.new(2.4, 2.6, 0.4), CFrame = frame * CFrame.new(width / 4, height * 0.55, -depth / 2 - 0.1), Color = P.Glass, Material = Enum.Material.Glass, Parent = model })
	for _, side in { -1, 1 } do
		Kit.Part({
			Class = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(width + 1.2, depth * 0.5, depth / 2 + 0.8),
			CFrame = frame * CFrame.new(0, height + depth * 0.25, side * (depth / 4 + 0.4)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			Color = Color3.fromRGB(150, 120, 70),
			Material = Enum.Material.Fabric, -- thatch
			Parent = model,
		})
	end
	Kit.Part({ Name = "Chimney", Size = Vector3.new(2, 7, 2), CFrame = frame * CFrame.new(width / 2 - 2, height + 3, depth / 4), Color = P.Stone[1], Material = Enum.Material.Brick, Parent = model })
end

local function barn(parent: Instance, frame: CFrame)
	local model = Kit.Model("Barn", parent)
	local width, depth, height = 20, 28, 15
	Kit.Part({ Name = "Body", Size = Vector3.new(width, height, depth), CFrame = frame * CFrame.new(0, height / 2, 0), Color = Color3.fromRGB(160, 62, 50), Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Detail({ Name = "Doors", Size = Vector3.new(9, 11, 0.5), CFrame = frame * CFrame.new(0, 5.5, -depth / 2 - 0.15), Color = Color3.fromRGB(236, 226, 206), Material = Enum.Material.WoodPlanks, Parent = model })
	for _, side in { -1, 1 } do
		Kit.Part({
			Class = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(depth + 1.5, 9, width / 2 + 1),
			CFrame = frame * CFrame.new(side * (width / 4 + 0.5), height + 4.5, 0) * CFrame.Angles(0, math.rad(-90 * side), 0),
			Color = Color3.fromRGB(90, 70, 60),
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
end

local function windmill(parent: Instance, base: Vector3, facing: number)
	local model = Kit.Model("Windmill", parent)
	local stone = Color3.fromRGB(214, 204, 186)
	Kit.Part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(24, 14, 14), CFrame = CFrame.new(base + Vector3.new(0, 12, 0)) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Plaster, Parent = model })
	Kit.Part({ Name = "Upper", Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 11, 11), CFrame = CFrame.new(base + Vector3.new(0, 30, 0)) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Plaster, Parent = model })
	Kit.Part({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.one * 12, Position = base + Vector3.new(0, 36, 0), Color = Color3.fromRGB(120, 84, 60), Material = Enum.Material.WoodPlanks, Parent = model })
	-- Sails on a hub out front; the client spins the "Sails" model.
	local front = CFrame.new(base + Vector3.new(0, 33, 0)) * CFrame.Angles(0, facing, 0) * CFrame.new(0, 0, -7.5)
	local sails = Kit.Model("Sails", model)
	local hub = Kit.Part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 2.4, 2.4), CFrame = front * Kit.ALONG_LOOK, Color = P.Timber, Material = Enum.Material.Wood, Parent = sails })
	sails.PrimaryPart = hub
	for i = 0, 3 do
		local turn = front * CFrame.Angles(0, 0, i * math.pi / 2)
		Kit.Detail({ Name = "Spar", Size = Vector3.new(0.8, 22, 0.6), CFrame = turn * CFrame.new(0, 11.5, -0.6), Color = P.Timber, Material = Enum.Material.Wood, Parent = sails })
		Kit.Detail({ Name = "Sail", Size = Vector3.new(4, 17, 0.2), CFrame = turn * CFrame.new(2.4, 13.5, -0.5), Color = Color3.fromRGB(236, 228, 210), Material = Enum.Material.Fabric, Parent = sails })
	end
	sails:SetAttribute("Speed", 0.6) -- radians a second, round the hub's look axis
	CollectionService:AddTag(sails, Config.Tags.Spin)
end

local function farms(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Farms"
	folder.Parent = parent
	local region = Layout.Farms
	local spots = scatter(region, 7, 70, 16, rng)
	for i, p in spots do
		local facing = Geo.AngleOf(-p) -- face the town
		local frame = CFrame.new(p) * CFrame.Angles(0, facing + math.pi, 0)
		if i == 1 then
			windmill(folder, p, facing + math.pi)
			addAnchor(p)
			occupy(p, 12)
		elseif i == 2 then
			barn(folder, frame)
			occupy(p, 18)
		else
			cottage(folder, frame, rng)
			occupy(p, 11)
		end
	end
	for _ = 1, 14 do
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner, region.Outer))
		if clearSpot(p, 6) and free(p, 4) then
			occupy(p, 4)
			Kit.Part({ Name = "Haystack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 7, 7), CFrame = CFrame.new(p + Vector3.new(0, 2, 0)) * Kit.UPRIGHT, Color = Color3.fromRGB(222, 190, 100), Material = Enum.Material.Fabric, Parent = folder })
			Kit.Part({ Name = "HaystackTop", Shape = Enum.PartType.Ball, Size = Vector3.one * 6.4, Position = p + Vector3.new(0, 4.2, 0), Color = Color3.fromRGB(222, 190, 100), Material = Enum.Material.Fabric, Parent = folder })
		end
	end
end

-- === The road, the plains, the hills =========================================

local function road(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Road"
	folder.Parent = parent
	local start = W.WallRadius + W.WallThickness + 50
	-- The fence stops short of the hills, and leaves gaps where the plains
	-- roads branch off.
	for z = start, W.LandRadius - 132, 12 do
		for _, side in { -1, 1 } do
			local x = Layout.RoadX(z) + side * (Layout.RoadHalfWidth + 2)
			local nextX = Layout.RoadX(z + 12) + side * (Layout.RoadHalfWidth + 2)
			local junction = math.min(Layout.DistanceToPlainRoads(Vector3.new(x, 0, z)), Layout.DistanceToPlainRoads(Vector3.new(nextX, 0, z + 12)))
			if not Geo.InRiver(x, z, 4) and junction > Layout.RoadHalfWidth + 4 then
				Kit.Detail({ Name = "FencePost", Size = Vector3.new(0.7, 4, 0.7), Position = Vector3.new(x, 2, z), Color = P.Timber, Material = Enum.Material.Wood, Parent = folder })
				Kit.Rod(folder, "FenceRail", Vector3.new(x, 2.8, z), Vector3.new(nextX, 2.8, z + 12), 0.35, P.Timber, Enum.Material.Wood, true)
			end
		end
	end
	occupy(Vector3.new(Layout.RoadX(start + 60) - Layout.RoadHalfWidth - 7, 0, start + 60), 7)
	-- A signpost and an old cart near the gate.
	local sign = Vector3.new(Layout.RoadX(start) + Layout.RoadHalfWidth + 6, 0, start + 8)
	Kit.Part({ Name = "SignPost", Size = Vector3.new(0.8, 9, 0.8), Position = sign + Vector3.new(0, 4.5, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = folder })
	Kit.Detail({ Name = "SignBoard", Size = Vector3.new(6, 1.6, 0.4), CFrame = CFrame.new(sign + Vector3.new(1.5, 7.6, 0)) * CFrame.Angles(0, 0, math.rad(-8)), Color = Color3.fromRGB(176, 140, 96), Material = Enum.Material.Wood, Parent = folder })
	local cart = CFrame.new(Vector3.new(Layout.RoadX(start + 60) - Layout.RoadHalfWidth - 7, 0, start + 60)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
	Kit.Part({ Name = "CartBed", Size = Vector3.new(6, 1, 10), CFrame = cart * CFrame.new(0, 2.6, 0), Color = Color3.fromRGB(130, 96, 62), Material = Enum.Material.WoodPlanks, Parent = folder })
	for _, x in { -3.4, 3.4 } do
		Kit.Detail({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4.6, 4.6), CFrame = cart * CFrame.new(x, 2.3, 1), Color = P.Timber, Material = Enum.Material.Wood, Parent = folder })
	end
end

local function plains(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Plains"
	folder.Parent = parent
	local everywhere = { Angle = math.pi, Spread = math.pi, Inner = WALL_OUT + 40, Outer = W.LandRadius - 30 }

	-- Groves of giant trees dotted over the open plains: islands to swing
	-- between, so no stretch of grass is too wide to cross on the cables.
	-- Every other one has a supply crate with a beam.
	local groves = 0
	for _, centre in scatter({ Angle = math.pi, Spread = math.pi, Inner = 560, Outer = W.LandRadius - 90 }, 60, 190, 30, rng) do
		if groves < 26 and not busy(centre, 90) then
			groves += 1
			local grove = Instance.new("Folder")
			grove.Name = "Grove"
			grove.Parent = folder
			local trees = rng:NextInteger(3, 5)
			for t = 1, trees do
				local angle = t / trees * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
				local p = centre + Vector3.new(math.sin(angle), 0, math.cos(angle)) * (if t == 1 then 0 else rng:NextNumber(40, 70))
				local height = rng:NextNumber(110, 160)
				if clearSpot(p, 14) and not busy(p, 20) and free(p, 10) and Geo.RadiusOf(p) < W.BoundaryRadius - 20 then
					giantTree(grove, grounded(p, 3), height, rng)
				end
			end
			local crate = centre + Vector3.new(16, 0, 10)
			if groves % 2 == 1 and clearSpot(crate, 6) and free(crate, 4) then
				supplies(grove, grounded(crate), true)
				occupy(crate, 5)
			end
		end
	end

	for _, p in scatter(everywhere, 200, 46, 10, rng) do
		if not busy(p, 0) then
			if rng:NextNumber() < 0.75 then
				Kit.Tree(folder, grounded(p, 2), rng:NextNumber(20, 34), rng)
				occupy(p, 3)
			else
				local size = rng:NextNumber(4, 9)
				Kit.Part({ Name = "Boulder", Size = Vector3.new(size * 1.3, size, size), CFrame = CFrame.new(grounded(p, 1) + Vector3.new(0, size * 0.35, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(136, 132, 124), Material = Enum.Material.Slate, Parent = folder })
				occupy(p, size * 0.7)
			end
		end
	end
	-- Firs along the hills, standing on the slopes (not buried in them).
	for i = 1, 170 do
		local angle = i / 170 * math.pi * 2 + rng:NextNumber(-0.02, 0.02)
		local p = Geo.Polar(angle, W.LandRadius + rng:NextNumber(-60, 30))
		local height = rng:NextNumber(26, 44)
		if clearSpot(p, 6) and free(p, 3) then
			Kit.Fir(folder, grounded(p, 1.5), height, rng)
		end
	end
end

-- === The Great Forest (east) ================================================
-- Trees taller than the wall and nothing else: the place to swing. A few
-- trunks carry hunters' platforms with supplies and torches.

local function greatForest(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "GreatForest"
	folder.Parent = parent
	local spots = scatter(Layout.GreatForest, 76, 64, 16, rng)
	for i, spot in spots do
		local p = grounded(spot, 3) -- the far edge reaches the hills
		local height = rng:NextNumber(160, 230)
		local platform = i % 22 == 1
		local deckY = if platform then height * rng:NextNumber(0.35, 0.5) else nil
		local _, trunk = giantTree(folder, p, height, rng, deckY)
		if deckY then
			treePlatform(folder, p, trunk, deckY, true)
		end
	end
	-- A few old trunks leaning out over the river from its south bank: a
	-- ramp to run up, and something low to hook over the water.
	for _, x in { 800, 930, 1060 } do
		for try = 0, 4 do
			local bankX = x + try * 18
			local riverZ = Geo.RiverZ(bankX)
			local base = Vector3.new(bankX, -2, riverZ + W.River.Width / 2 + 8)
			local tip = Vector3.new(bankX + 10, 44, riverZ - W.River.Width / 2 - 22)
			if Layout.InRegion(base, Layout.GreatForest) and free(base, 10) and free(tip, 10) then
				local diameter = rng:NextNumber(6, 8)
				Kit.Rod(folder, "LeaningTrunk", base, tip, diameter, P.Bark, Enum.Material.Wood)
				Kit.Part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(24, 32), Position = tip + Vector3.new(0, 6, 0), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = folder })
				addAnchor(tip)
				occupy(base, diameter)
				occupy(tip, diameter)
				break
			end
		end
	end
end

-- === The Training Grounds (north) ===========================================
-- Practice trees and wooden giant dummies with a target on the back of the
-- neck, some up on stilts. Cut them for practice (HunterService).

local function dummy(parent: Instance, base: CFrame, height: number, stilt: number)
	local model = Kit.Model("TrainingDummy", parent)
	local wood = Color3.fromRGB(150, 112, 72)
	local frame = base * CFrame.new(0, stilt, 0)
	for _, x in { -2.5, 2.5 } do
		Kit.Part({ Name = "Post", Size = Vector3.new(1, stilt + height * 0.55, 1), CFrame = base * CFrame.new(x, (stilt + height * 0.55) / 2, 1.2), Color = Kit.Palette.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	Kit.Part({ Name = "Body", Size = Vector3.new(height * 0.32, height * 0.5, 1.2), CFrame = frame * CFrame.new(0, height * 0.42, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Part({ Name = "Head", Size = Vector3.new(height * 0.2, height * 0.2, 1.2), CFrame = frame * CFrame.new(0, height * 0.8, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = model })
	for _, side in { -1, 1 } do
		Kit.Part({ Name = "Arm", Size = Vector3.new(height * 0.08, height * 0.42, 1), CFrame = frame * CFrame.new(side * height * 0.22, height * 0.45, 0) * CFrame.Angles(0, 0, side * 0.35), Color = wood, Material = Enum.Material.WoodPlanks, Parent = model })
	end
	-- The target: on the back of the neck (+Z, the side away from its face).
	local nape = Kit.Part({ Name = "DummyNape", Size = Vector3.new(height * 0.12, height * 0.1, 0.6), CFrame = frame * CFrame.new(0, height * 0.68, 0.9), Color = Color3.fromRGB(230, 110, 50), Material = Enum.Material.SmoothPlastic, Parent = model })
	CollectionService:AddTag(nape, Config.Tags.DummyNape)
end

local function training(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "TrainingGrounds"
	folder.Parent = parent
	local region = Layout.Training
	-- The crate and the banner first, so nothing is built on them.
	local crate = Geo.Polar(region.Angle, region.Inner + 30)
	supplies(folder, crate, true)
	occupy(crate, 6)
	local pole = Geo.Polar(region.Angle, region.Inner + 6)
	occupy(pole, 4)
	for _, p in scatter(region, 16, 52, 10, rng) do
		giantTree(folder, p, rng:NextNumber(85, 125), rng)
	end
	-- Dummies stand in the clearings, well away from the trunks and each
	-- other (free() keeps them 10 studs off anything).
	local placed = 0
	for _ = 1, 60 do
		if placed >= 18 then
			break
		end
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner + 20, region.Outer - 20))
		local base = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local height = rng:NextNumber(18, 32)
		if clearSpot(p, 8) and free(p, 10 + height * 0.2) then
			placed += 1
			dummy(folder, base, height, if placed % 3 == 0 then rng:NextNumber(14, 34) else 0)
			occupy(p, height * 0.2)
		end
	end
	Kit.Rod(folder, "BannerPole", pole, pole + Vector3.new(0, 44, 0), 0.8, Kit.Palette.Iron, Enum.Material.Metal)
	Kit.Banner(folder, CFrame.new(pole + Vector3.new(0, 42, -0.6)) * CFrame.Angles(0, region.Angle, 0), 10, 18)
end

-- === The old castle (west) ==================================================
-- A ruined hilltop keep: curtain walls with a broken stretch, corner towers,
-- a tall round keep. Good perches, a supply crate in the courtyard.

local function castle(parent: Instance)
	local spec = Layout.Castle
	local model = Kit.Model("OldCastle", parent)
	local centre = Geo.Polar(spec.Angle, spec.Radius, spec.Top)
	-- Face the town.
	local base = CFrame.new(centre) * CFrame.Angles(0, spec.Angle, 0)
	local stone = Color3.fromRGB(150, 144, 132)
	local dark = Color3.fromRGB(118, 112, 102)
	Kit.Part({ Name = "Foundation", Size = Vector3.new(76, 26, 76), CFrame = base * CFrame.new(0, -13, 0), Color = dark, Material = Enum.Material.Slate, Parent = model })
	local half = 32
	for i = 0, 3 do
		local side = base * CFrame.Angles(0, i * math.pi / 2, 0)
		local broken = i == 2
		local height = if broken then 9 else 22
		if i == 0 then
			-- The gate side (facing town): two walls either side of an opening.
			for _, x in { -1, 1 } do
				Kit.Part({ Name = "CurtainWall", Size = Vector3.new(half - 7, height, 4), CFrame = side * CFrame.new(x * (half / 2 + 3.5), height / 2, -half), Color = stone, Material = Enum.Material.Slate, Parent = model })
			end
			Kit.Part({ Name = "GateArch", Size = Vector3.new(14, 6, 4.4), CFrame = side * CFrame.new(0, height - 3, -half), Color = dark, Material = Enum.Material.Slate, Parent = model })
		else
			Kit.Part({ Name = "CurtainWall", Size = Vector3.new(half * 2, height, 4), CFrame = side * CFrame.new(0, height / 2, -half), Color = stone, Material = Enum.Material.Slate, Parent = model })
		end
		if not broken then
			for x = -half + 4, half - 4, 8 do
				Kit.Part({ Name = "Merlon", Size = Vector3.new(3.5, 3, 4.4), CFrame = side * CFrame.new(x, height + 1.5, -half), Color = stone, Material = Enum.Material.Slate, Parent = model })
			end
		else
			for k = 1, 6 do
				Kit.Part({ Name = "Rubble", Size = Vector3.new(4 + k % 3, 3 + k % 2 * 2, 4), CFrame = side * CFrame.new(-half + k * 9, 1.5, -half - 4) * CFrame.Angles(0.2 * k, 0.5 * k, 0.1), Color = stone, Material = Enum.Material.Slate, Parent = model })
			end
		end
		-- Corner tower (one of them half fallen).
		local towerHeight = if i == 3 then 24 else 42
		local corner = side * CFrame.new(half, 0, -half)
		Kit.Part({ Name = "CornerTower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(towerHeight, 13, 13), CFrame = corner * CFrame.new(0, towerHeight / 2, 0) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Slate, Parent = model })
		Kit.Part({ Name = "TowerCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 15, 15), CFrame = corner * CFrame.new(0, towerHeight + 1, 0) * Kit.UPRIGHT, Color = dark, Material = Enum.Material.Slate, Parent = model })
	end
	-- The keep: a tall round tower with a pointed roof.
	Kit.Part({ Name = "Keep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(74, 24, 24), CFrame = base * CFrame.new(0, 37, 8) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Slate, Parent = model })
	for k, size in { 27, 20, 13, 6 } do
		Kit.Part({ Name = "KeepRoof", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, size, size), CFrame = base * CFrame.new(0, 74 + k * 4.5, 8) * Kit.UPRIGHT, Color = Color3.fromRGB(80, 74, 86), Material = Enum.Material.Slate, Parent = model })
	end
	for _, y in { 22, 44, 62 } do
		Kit.Detail({ Name = "Window", Size = Vector3.new(3, 5, 0.6), CFrame = base * CFrame.new(0, y, 8 - 12.1), Color = Color3.fromRGB(40, 34, 30), Parent = model })
	end
	Kit.Banner(model, base * CFrame.new(0, 66, 8 - 12.4), 8, 14)
	supplies(model, (base * CFrame.new(-14, 0, -12)).Position, true)
	-- Torches either side of the top of the ramp up to the gate.
	for _, x in { -9, 9 } do
		Kit.Torch(model, base * CFrame.new(x, 0, -half - 4))
	end
	addAnchor(centre)
end

-- === Signal towers ==========================================================
-- Tall timber towers beside the roads and in a ring round the outer
-- plains: something to hook across the open grass. Every other one has a
-- supply crate on top, with a beam.

local function signalTower(parent: Instance, at: Vector3, height: number, stocked: boolean)
	local model = Kit.Model("SignalTower", parent)
	local timber = Kit.Palette.Timber
	local foot, top = 6, 3.5
	local corners = { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) }
	for i, c in corners do
		Kit.Rod(model, "Leg", at + c * foot, at + c * top + Vector3.new(0, height, 0), 1.1, timber, Enum.Material.Wood)
		local n = corners[i % 4 + 1]
		for _, t in { 0.33, 0.66 } do
			local spread = foot + (top - foot) * t
			Kit.Rod(model, "Brace", at + c * spread + Vector3.new(0, height * t, 0), at + n * spread + Vector3.new(0, height * t, 0), 0.6, timber, Enum.Material.Wood, true)
		end
	end
	Kit.Part({ Name = "Deck", Size = Vector3.new(top * 2 + 4, 1, top * 2 + 4), Position = at + Vector3.new(0, height + 0.5, 0), Color = Color3.fromRGB(140, 104, 66), Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(top * 2 + 5, 4, top + 2.5), CFrame = CFrame.new(at + Vector3.new(0, height + 9, -(top + 2.5) / 2)), Color = Kit.Palette.Roof[3], Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(top * 2 + 5, 4, top + 2.5), CFrame = CFrame.new(at + Vector3.new(0, height + 9, (top + 2.5) / 2)) * CFrame.Angles(0, math.pi, 0), Color = Kit.Palette.Roof[3], Material = Enum.Material.Slate, Parent = model })
	for _, c in corners do
		Kit.Detail({ Name = "RoofPost", Size = Vector3.new(0.6, 7, 0.6), Position = at + c * (top + 1) + Vector3.new(0, height + 4, 0), Color = timber, Material = Enum.Material.Wood, Parent = model })
	end
	Kit.Torch(model, CFrame.new(at + Vector3.new(top, height + 1, top)))
	if stocked then
		supplies(model, at + Vector3.new(0, height + 1, 0), true)
	end
	addAnchor(at)
	occupy(at, foot + 2)
end

local function towerSpot(p: Vector3): boolean
	return not Geo.InRiver(p.X, p.Z, 10) and not Geo.InCastleHill(p, 10) and Geo.RadiusOf(p) > WALL_OUT + 40 and free(p, 8)
end

local function signalTowers(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "SignalTowers"
	folder.Parent = parent
	local count = 0
	for _, road in Layout.Roads do
		local carried = 60 -- distance walked since the last tower
		for i = 1, #road - 1 do
			local a, b = road[i], road[i + 1]
			local length = (b - a).Magnitude
			local along = (b - a).Unit
			local side = Vector3.new(along.Z, 0, -along.X)
			local d = 130 - carried
			while d < length do
				local p = a + along * d + side * (Layout.RoadHalfWidth + 9)
				local wooded = Layout.InRegion(p, Layout.GreatForest) or Layout.InRegion(p, Layout.Training) or Layout.InRegion(p, Layout.Forest)
				local height = rng:NextNumber(58, 74)
				if not wooded and towerSpot(p) then
					count += 1
					signalTower(folder, grounded(p), height, count % 2 == 0)
				end
				d += 130
			end
			carried = length - (d - 130)
		end
	end
	-- And down the south road from the gate, on alternate sides.
	local side = 1
	for z = W.WallRadius + 260, W.LandRadius - 140, 140 do
		local p = Vector3.new(Layout.RoadX(z) + side * (Layout.RoadHalfWidth + 12), 0, z)
		local height = rng:NextNumber(58, 74)
		if towerSpot(p) then
			count += 1
			signalTower(folder, grounded(p), height, count % 2 == 0)
		end
		side = -side
	end
end

-- A ring of towers round the outer plains (where the roads don't go),
-- wherever nothing else is close enough to hook.
local function outerTowers(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "OuterTowers"
	folder.Parent = parent
	local count = 0
	for degrees = 0, 351, 9 do
		local p = Geo.Polar(math.rad(degrees), 1050 + rng:NextNumber(-25, 25))
		local height = rng:NextNumber(62, 78)
		if anchorDistance(p) > 110 and not busy(p, 30) and clearSpot(p, 12) and towerSpot(p) then
			count += 1
			signalTower(folder, grounded(p), height, count % 2 == 1)
		end
	end
end

-- === Bridges where the plains roads cross the river ==========================

local function roadBridge(parent: Instance, crossing: Vector3, along: Vector3)
	local model = Kit.Model("Bridge", parent)
	local tangent = Vector3.new(1, 0, (Geo.RiverZ(crossing.X + 1) - Geo.RiverZ(crossing.X - 1)) / 2).Unit
	local sine = math.max(math.abs(along.X * tangent.Z - along.Z * tangent.X), 0.4)
	local length = math.min((W.River.Width + 16) / sine, 90)
	local width = Layout.RoadHalfWidth * 2
	local frame = CFrame.lookAt(crossing, crossing + along)
	local wood = Color3.fromRGB(140, 104, 66)
	Kit.Part({ Name = "Deck", Size = Vector3.new(width, 1.2, length), CFrame = frame * CFrame.new(0, 0.4, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = model })
	for _, x in { -1, 1 } do
		Kit.Part({ Name = "Rail", Size = Vector3.new(0.8, 1, length), CFrame = frame * CFrame.new(x * (width / 2 - 0.4), 3, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		for _, z in { -0.5, -0.17, 0.17, 0.5 } do
			Kit.Detail({ Name = "RailPost", Size = Vector3.new(0.7, 3, 0.7), CFrame = frame * CFrame.new(x * (width / 2 - 0.4), 1.8, z * (length - 1)), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		end
		Kit.Part({ Name = "Pier", Size = Vector3.new(2, 14, 2), CFrame = frame * CFrame.new(x * (width / 2 - 2), -7, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	occupy(crossing, length / 2)
end

local function bridges(parent: Instance)
	for _, road in Layout.Roads do
		for i = 1, #road - 1 do
			local a, b = road[i], road[i + 1]
			local length = (b - a).Magnitude
			local along = (b - a).Unit
			local function side(d: number): number
				local p = a + along * d
				return p.Z - Geo.RiverZ(p.X)
			end
			local d = 0
			while d < length do
				local nextD = math.min(d + 2, length)
				if side(d) * side(nextD) < 0 and Geo.InRiver((a + along * d).X, (a + along * d).Z, 4) then
					roadBridge(parent, a + along * ((d + nextD) / 2), along)
				end
				d = nextD
			end
		end
	end
end

-- === Supplies and hooks everywhere ===========================================

-- A beam-lit crate on its own, near `p` (out where the towers are few).
local function lonelyCrate(parent: Instance, p: Vector3)
	if crateDistance(p) < 160 then
		return
	end
	for try = 0, 5 do
		local spot = p + Geo.Polar(try * 1.3, try * 14)
		if clearSpot(spot, 8) and free(spot, 6) then
			supplies(parent, grounded(spot), true)
			occupy(spot, 5)
			return
		end
	end
end

-- Last pass: on a 60-stud grid, any spot still more than 140 studs from
-- something to hook gets a lone giant tree.
local function fillGaps(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "LoneGiants"
	folder.Parent = parent
	local CELL = 60
	local reach = W.LandRadius - 100
	for x = -reach, reach, CELL do
		for z = -reach, reach, CELL do
			local centre = Vector3.new(x + CELL / 2, 0, z + CELL / 2)
			local r = Geo.RadiusOf(centre)
			if r > WALL_OUT + 60 and r < reach and anchorDistance(centre) > 140 then
				local height = rng:NextNumber(100, 150)
				for try = 0, 6 do
					local p = centre + Geo.Polar(try * 2.1, try * 9)
					if clearSpot(p, 14) and free(p, 12) and not nearRegion(p, Layout.Farms, 0) then
						giantTree(folder, grounded(p, 3), height, rng)
						break
					end
				end
			end
		end
	end
end

-- Where giants appear: out on the plains south of the wall, in the open
-- (never in the line of the forest or the farms), facing the wall.
function Wilds.GiantSpawns(): { Vector3 }
	local spawns = {}
	local function inLine(angle: number, region: Region): boolean
		return math.abs(Geo.AngleDelta(region.Angle, angle)) < region.Spread + math.rad(4)
	end
	for i = -13, 13 do
		local angle = W.GateAngle + i * math.rad(7)
		local p = Geo.Polar(angle, W.GiantSpawnRadius)
		local clear = not (inLine(angle, Layout.Forest) or inLine(angle, Layout.Farms) or nearRegion(p, Layout.GreatForest, 25))
		if clear and not Geo.InRiver(p.X, p.Z, 10) and not Geo.InCastleHill(p, 20) then
			table.insert(spawns, p)
		end
	end
	if #spawns == 0 then
		table.insert(spawns, Geo.Polar(W.GateAngle, W.GiantSpawnRadius))
	end
	return spawns
end

-- The edge of the world: an invisible wall just inside the hill ring.
-- Hooks and the camera go through it (CanQuery off); nobody walks or
-- flies through it. Persistent, so it's always there with streaming on.
function Wilds.BuildBoundary(parent: Instance)
	local model = Kit.Model("MapBoundary", parent)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local radius, height = W.BoundaryRadius, W.BoundaryHeight
	local n = 72
	local length = 2 * radius * math.tan(math.pi / n) + 2
	for i = 0, n - 1 do
		local angle = i / n * math.pi * 2
		Kit.Part({
			Name = "Boundary",
			Size = Vector3.new(length, height, 8),
			CFrame = CFrame.new(Geo.Polar(angle, radius + 4, height / 2 - 40)) * CFrame.Angles(0, angle, 0),
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
			Parent = model,
		})
	end
	CollectionService:AddTag(model, Config.Tags.MapBoundary)
end

function Wilds.Build(parent: Instance, rng: Random)
	footprints, anchors, crates = {}, {}, {}
	local folder = Instance.new("Folder")
	folder.Name = "Wilds"
	folder.Parent = parent
	castle(folder)
	forest(folder, rng)
	greatForest(folder, rng)
	training(folder, rng)
	farms(folder, rng)
	road(folder, rng)
	bridges(folder)
	signalTowers(folder, rng)
	plains(folder, rng)
	outerTowers(folder, rng)
	-- Supplies out in the far north and north-west, and deep in the Great
	-- Forest, where nothing else is.
	for _, spot in { { 170, 1060 }, { 205, 1060 }, { 238, 1060 }, { 90, 1130 }, { 62, 1060 } } do
		lonelyCrate(folder, Geo.Polar(math.rad(spot[1]), spot[2]))
	end
	fillGaps(folder, rng)
end

return Wilds
