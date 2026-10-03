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

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local Wilds = {}

local W = Config.World
local P = Kit.Palette

local function onRoad(p: Vector3, margin: number): boolean
	return p.Z > W.WallRadius and math.abs(p.X - Layout.RoadX(p.Z)) < Layout.RoadHalfWidth + margin
end

local function clearSpot(p: Vector3, margin: number): boolean
	return not onRoad(p, margin) and not Geo.InRiver(p.X, p.Z, margin) and Geo.RadiusOf(p) > W.WallRadius + W.WallThickness + margin
end

-- Random points in a polar region, at least `spacing` apart.
local function scatter(region: { Angle: number, Spread: number, Inner: number, Outer: number }, count: number, spacing: number, margin: number, rng: Random): { Vector3 }
	local points: { Vector3 } = {}
	for _ = 1, count * 30 do
		if #points >= count then
			break
		end
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner, region.Outer))
		local ok = clearSpot(p, margin)
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

local function giantTree(parent: Instance, base: Vector3, height: number, rng: Random): (Model, number)
	local model = Kit.Model("GiantTree", parent)
	local trunk = height * 0.1
	Kit.Part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, trunk, trunk), CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * Kit.UPRIGHT, Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	-- Root buttresses: wedges sloping down and away from the trunk (a
	-- wedge's tall face is its local +Z, here turned toward the trunk).
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local out = Geo.Polar(angle, 1)
		local foot = base + out * trunk * 0.7 + Vector3.new(0, height * 0.06, 0)
		Kit.Part({ Class = "WedgePart", Name = "Root", Size = Vector3.new(trunk * 0.3, height * 0.12, trunk * 0.9), CFrame = CFrame.lookAt(foot, foot + out), Color = P.Bark, Material = Enum.Material.Wood, Parent = model })
	end
	-- Thick branches, each ending in a leafy cluster.
	for _ = 1, rng:NextInteger(4, 6) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local y = height * rng:NextNumber(0.42, 0.8)
		local length = height * rng:NextNumber(0.18, 0.3)
		local start = base + Vector3.new(0, y, 0)
		local tip = start + Geo.Polar(angle, length) + Vector3.new(0, length * rng:NextNumber(0.12, 0.4), 0)
		Kit.Rod(model, "Branch", start, tip, trunk * 0.32, P.Bark, Enum.Material.Wood)
		Kit.Part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * height * rng:NextNumber(0.15, 0.22), Position = tip + Vector3.new(0, height * 0.03, 0), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, Parent = model })
	end
	for i = 1, 3 do
		local size = height * rng:NextNumber(0.26, 0.34)
		Kit.Part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = base + Vector3.new(rng:NextNumber(-0.08, 0.08) * height, height * (0.9 + i * 0.05), rng:NextNumber(-0.08, 0.08) * height), Color = P.Leaves[rng:NextInteger(1, #P.Leaves)], Material = Enum.Material.Grass, Parent = model })
	end
	return model, trunk
end

-- A square wooden deck round a trunk, railings and a supply crate on it.
local function treePlatform(parent: Instance, base: Vector3, trunk: number, y: number)
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
		Kit.Rod(model, "Strut", corner, base + Vector3.new(0, y - size * 0.45, 0), 0.8, P.Timber, Enum.Material.Wood)
	end
	Kit.SupplyStation(model, (deck * CFrame.new(trunk / 2 + 5, 0.6, 0)).Position, true)
end

local function forest(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "GiantForest"
	folder.Parent = parent
	local spots = scatter(Layout.Forest, 30, 46, 14, rng)
	for i, p in spots do
		local height = rng:NextNumber(115, 160)
		local _, trunk = giantTree(folder, p, height, rng)
		if i == 1 then
			treePlatform(folder, p, trunk, height * 0.42)
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
		elseif i == 2 then
			barn(folder, frame)
		else
			cottage(folder, frame, rng)
		end
	end
	for _ = 1, 14 do
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner, region.Outer))
		if clearSpot(p, 6) then
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
	for z = start, W.LandRadius - 20, 12 do
		for _, side in { -1, 1 } do
			local x = Layout.RoadX(z) + side * (Layout.RoadHalfWidth + 2)
			local nextX = Layout.RoadX(z + 12) + side * (Layout.RoadHalfWidth + 2)
			if not Geo.InRiver(x, z, 4) then
				Kit.Detail({ Name = "FencePost", Size = Vector3.new(0.7, 4, 0.7), Position = Vector3.new(x, 2, z), Color = P.Timber, Material = Enum.Material.Wood, Parent = folder })
				Kit.Rod(folder, "FenceRail", Vector3.new(x, 2.8, z), Vector3.new(nextX, 2.8, z + 12), 0.35, P.Timber, Enum.Material.Wood)
			end
		end
	end
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
	local everywhere = { Angle = math.pi, Spread = math.pi, Inner = W.WallRadius + W.WallThickness + 40, Outer = W.LandRadius - 30 }
	local castleSpot = Geo.Polar(Layout.Castle.Angle, Layout.Castle.Radius)
	local function busy(p: Vector3, margin: number): boolean
		return Layout.InRegion(p, Layout.Forest)
			or Layout.InRegion(p, Layout.Farms)
			or Layout.InRegion(p, Layout.GreatForest)
			or Layout.InRegion(p, Layout.Training)
			or Geo.Flat(p - castleSpot).Magnitude < Layout.Castle.HillRadius + margin
	end

	-- Groves of giant trees dotted over the open plains: islands to swing
	-- between, so no stretch of grass is too wide to cross on the cables.
	local groves = 0
	for _, centre in scatter({ Angle = math.pi, Spread = math.pi, Inner = 560, Outer = W.LandRadius - 120 }, 30, 190, 30, rng) do
		if groves < 16 and not busy(centre, 90) then
			groves += 1
			local grove = Instance.new("Folder")
			grove.Name = "Grove"
			grove.Parent = folder
			local trees = rng:NextInteger(3, 6)
			for t = 1, trees do
				local angle = t / trees * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
				local p = centre + Vector3.new(math.sin(angle), 0, math.cos(angle)) * (if t == 1 then 0 else rng:NextNumber(40, 70))
				if clearSpot(p, 14) then
					giantTree(grove, p, rng:NextNumber(110, 160), rng)
				end
			end
		end
	end

	for _, p in scatter(everywhere, 200, 46, 10, rng) do
		if not busy(p, 0) then
			if rng:NextNumber() < 0.75 then
				Kit.Tree(folder, p, rng:NextNumber(20, 34), rng)
			else
				local size = rng:NextNumber(4, 9)
				Kit.Part({ Name = "Boulder", Size = Vector3.new(size * 1.3, size, size), CFrame = CFrame.new(p + Vector3.new(0, size * 0.35, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(136, 132, 124), Material = Enum.Material.Slate, Parent = folder })
			end
		end
	end
	for i = 1, 170 do
		local angle = i / 170 * math.pi * 2 + rng:NextNumber(-0.02, 0.02)
		local p = Geo.Polar(angle, W.LandRadius + rng:NextNumber(-35, 25))
		if clearSpot(p, 6) then
			Kit.Fir(folder, p, rng:NextNumber(26, 44), rng)
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
	for i, p in spots do
		local height = rng:NextNumber(160, 230)
		local _, trunk = giantTree(folder, p, height, rng)
		if i % 22 == 1 then
			treePlatform(folder, p, trunk, height * rng:NextNumber(0.35, 0.5))
			Kit.Torch(folder, CFrame.new(p + Vector3.new(trunk / 2 + 2, 0, trunk / 2 + 2)))
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
	for _, p in scatter(region, 16, 52, 10, rng) do
		giantTree(folder, p, rng:NextNumber(85, 125), rng)
	end
	for i = 1, 18 do
		local p = Geo.Polar(region.Angle + rng:NextNumber(-region.Spread, region.Spread), rng:NextNumber(region.Inner + 20, region.Outer - 20))
		if clearSpot(p, 8) then
			local base = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			dummy(folder, base, rng:NextNumber(18, 32), if i % 3 == 0 then rng:NextNumber(14, 34) else 0)
		end
	end
	Kit.SupplyStation(folder, Geo.Polar(region.Angle, region.Inner + 30), true)
	local pole = Geo.Polar(region.Angle, region.Inner + 6)
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
	Kit.SupplyStation(model, (base * CFrame.new(-14, 0, -12)).Position, true)
	for _, x in { -9, 9 } do
		Kit.Torch(model, base * CFrame.new(x, 0, -half - 4))
	end
end

-- === Signal towers along the roads ==========================================
-- Tall timber towers every so often beside the roads: something to hook
-- across the open plains. Every other one has a supply crate on top.

local function signalTower(parent: Instance, at: Vector3, height: number, supplies: boolean)
	local model = Kit.Model("SignalTower", parent)
	local timber = Kit.Palette.Timber
	local foot, top = 6, 3.5
	local corners = { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) }
	for i, c in corners do
		Kit.Rod(model, "Leg", at + c * foot, at + c * top + Vector3.new(0, height, 0), 1.1, timber, Enum.Material.Wood)
		local n = corners[i % 4 + 1]
		for _, t in { 0.33, 0.66 } do
			local spread = foot + (top - foot) * t
			Kit.Rod(model, "Brace", at + c * spread + Vector3.new(0, height * t, 0), at + n * spread + Vector3.new(0, height * t, 0), 0.6, timber, Enum.Material.Wood)
		end
	end
	Kit.Part({ Name = "Deck", Size = Vector3.new(top * 2 + 4, 1, top * 2 + 4), Position = at + Vector3.new(0, height + 0.5, 0), Color = Color3.fromRGB(140, 104, 66), Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(top * 2 + 5, 4, top + 2.5), CFrame = CFrame.new(at + Vector3.new(0, height + 9, -(top + 2.5) / 2)), Color = Kit.Palette.Roof[3], Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(top * 2 + 5, 4, top + 2.5), CFrame = CFrame.new(at + Vector3.new(0, height + 9, (top + 2.5) / 2)) * CFrame.Angles(0, math.pi, 0), Color = Kit.Palette.Roof[3], Material = Enum.Material.Slate, Parent = model })
	for _, c in corners do
		Kit.Detail({ Name = "RoofPost", Size = Vector3.new(0.6, 7, 0.6), Position = at + c * (top + 1) + Vector3.new(0, height + 4, 0), Color = timber, Material = Enum.Material.Wood, Parent = model })
	end
	Kit.Torch(model, CFrame.new(at + Vector3.new(top, height + 1, top)))
	if supplies then
		Kit.SupplyStation(model, at + Vector3.new(0, height + 1, 0), false)
	end
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
				if not wooded and not Geo.InRiver(p.X, p.Z, 10) and Geo.RadiusOf(p) > W.WallRadius + W.WallThickness + 40 then
					count += 1
					signalTower(folder, p, rng:NextNumber(58, 74), count % 2 == 0)
				end
				d += 130
			end
			carried = length - (d - 130)
		end
	end
	-- And down the south road from the gate, on alternate sides.
	local side = 1
	for z = W.WallRadius + 260, W.LandRadius - 100, 140 do
		local p = Vector3.new(Layout.RoadX(z) + side * (Layout.RoadHalfWidth + 12), 0, z)
		if not Geo.InRiver(p.X, p.Z, 10) then
			count += 1
			signalTower(folder, p, rng:NextNumber(58, 74), count % 2 == 0)
		end
		side = -side
	end
end

-- Where giants appear: out on the southern plains, facing the wall.
function Wilds.GiantSpawns(): { Vector3 }
	local spawns = {}
	for i = -6, 6 do
		local angle = W.GateAngle + i * math.rad(14)
		table.insert(spawns, Geo.Polar(angle, W.WallRadius + 190))
	end
	return spawns
end

function Wilds.Build(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Wilds"
	folder.Parent = parent
	forest(folder, rng)
	greatForest(folder, rng)
	training(folder, rng)
	castle(folder)
	signalTowers(folder, rng)
	farms(folder, rng)
	road(folder, rng)
	plains(folder, rng)
end

return Wilds
