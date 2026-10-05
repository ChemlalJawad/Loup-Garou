--!strict
-- The town's districts and its tall landmarks, built to swing between.
--
--   * Districts, each with its own colour on banners, pennants and
--     signposts: High Town round the plaza (crimson: stone manors, spires,
--     balconies), the Crafts Ring (amber: workshops, awnings, carts) and
--     Wallside by the wall (green: packed timber houses, warehouses).
--   * The clock tower (west, before the market): a lookout gallery under
--     its spire, and four faces that glow at night.
--   * The river light (on the river's south bank, north-west): a striped
--     tower with a lantern on top, a dock and boats at its feet.
--   * The water mill (north-east bank): a mill house and its big wheel.
--   * The great granary (east, by the wall): a flat roof with a supply
--     crate on it.
--   * The river quays: stone kerbs along both banks, lamps, moored boats and
--     two arched footbridges.
-- Each landmark's main part is a point of interest (Config.Tags.POI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local TownLandmarks = {}

local W = Config.World
local P = Kit.Palette

export type District = { Name: string, Color: Color3 }
TownLandmarks.Districts = {
	HighTown = { Name = "High Town", Color = Color3.fromRGB(168, 44, 56) },
	Crafts = { Name = "Crafts Ring", Color = Color3.fromRGB(222, 150, 44) },
	Wallside = { Name = "Wallside", Color = Color3.fromRGB(58, 122, 70) },
} :: { [string]: District }
local D = TownLandmarks.Districts

local STONE = Color3.fromRGB(206, 198, 182)
local SLATE = Color3.fromRGB(92, 100, 118)

local function poi(part: BasePart, id: string, name: string)
	Kit.Poi(part, id, name, "Town")
end

-- Is the avenue clear at (angle, radius) for something `halfWidth` wide?
function TownLandmarks.AvenueClear(angle: number, radius: number, halfWidth: number): boolean
	for _, degrees in W.AvenueAngles do
		local wide = degrees == 0 or degrees == 180
		local clearance = (if wide then W.AvenueWidth + 6 else W.AvenueWidth) / 2 + halfWidth + 2
		if math.abs(Geo.AngleDelta(angle, math.rad(degrees))) * radius < clearance then
			return false
		end
	end
	return true
end

local function siteFrame(site: Layout.Site, radius: number): CFrame
	-- On `radius`, facing the plaza (local -Z inward).
	return CFrame.new(Geo.Polar(site.Angle, radius)) * CFrame.Angles(0, site.Angle, 0)
end

-- On the river's middle at `x`, looking downstream (east): local +X is the
-- south bank, -X the north bank.
local function riverFrame(x: number): CFrame
	local river = W.River
	local slope = river.Wave / river.WaveLength * math.cos(x / river.WaveLength)
	local p = Vector3.new(x, 0, Geo.RiverZ(x))
	return CFrame.lookAt(p, p + Vector3.new(1, 0, slope))
end

-- A rowing boat on the water, along `frame`'s look.
local function boat(parent: Instance, frame: CFrame, color: Color3)
	local model = Kit.Model("Boat", parent)
	local y = W.River.WaterY
	Kit.Part({ Name = "Hull", Size = Vector3.new(3.6, 1.6, 7), CFrame = frame * CFrame.new(0, y + 0.3, 0), Color = color, Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Bow", Size = Vector3.new(3.6, 1.6, 2.6), CFrame = frame * CFrame.new(0, y + 0.3, -4.8) * CFrame.Angles(0, 0, math.pi), Color = color, Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Detail({ Name = "Seat", Size = Vector3.new(3.2, 0.4, 1), CFrame = frame * CFrame.new(0, y + 1.2, 0.6), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
end

-- A little arched footbridge across the river at `x`: two ramps and a
-- level middle with low walls.
local function footbridge(parent: Instance, x: number)
	local model = Kit.Model("Footbridge", parent)
	local frame = riverFrame(x) * CFrame.Angles(0, math.rad(90), 0) -- now local Z runs across, toward the south bank
	local rise, ramp, middle = 5, 11, 14
	local stone = Color3.fromRGB(178, 168, 150)
	Kit.Part({ Name = "Deck", Size = Vector3.new(6, 1.2, middle), CFrame = frame * CFrame.new(0, rise - 0.6, 0), Color = stone, Material = Enum.Material.Cobblestone, Parent = model })
	for _, side in { -1, 1 } do
		-- Each ramp's tall end against the level middle.
		local centre = frame * CFrame.new(0, rise / 2, side * (middle / 2 + ramp / 2))
		Kit.Part({ Class = "WedgePart", Name = "Ramp", Size = Vector3.new(6, rise, ramp), CFrame = centre * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), Color = stone, Material = Enum.Material.Cobblestone, Parent = model })
		Kit.Part({ Name = "Parapet", Size = Vector3.new(0.8, 1.8, middle), CFrame = frame * CFrame.new(side * 3.2, rise + 0.9, 0), Color = Color3.fromRGB(150, 142, 128), Material = Enum.Material.Slate, Parent = model })
	end
	return model
end

-- Is `p` somewhere the quay can run: in town, off the roads and the sites.
local function onQuay(p: Vector3): boolean
	local r, angle = Geo.RadiusOf(p), Geo.AngleOf(p)
	if r > W.PerimeterRoad - 6 or Layout.InAnySite(angle, r) then
		return false
	end
	for _, ring in W.RingRoads do
		if math.abs(r - ring) < W.RoadWidth / 2 + 4 then
			return false
		end
	end
	return TownLandmarks.AvenueClear(angle, r, 4)
end

-- Stone kerbs along both banks, with lamps and a few moored boats.
local function quays(parent: Instance, rng: Random)
	local model = Kit.Model("Quays", parent)
	local step = 16
	local count = 0
	local x = -W.WallRadius
	while x < W.WallRadius do
		local frame = riverFrame(x + step / 2)
		local length = step * (1 / frame.LookVector.X) + 0.3
		count += 1
		for _, side in { -1, 1 } do
			local edge = frame * CFrame.new(side * 13.8, 0, 0)
			if onQuay(edge.Position) then
				Kit.Part({ Name = "Quay", Size = Vector3.new(1.4, 2.2, length), CFrame = edge * CFrame.new(0, 1.1, 0), Color = Color3.fromRGB(160, 152, 136), Material = Enum.Material.Slate, Parent = model })
				local lamp = frame * CFrame.new(side * 15.8, 0, 0)
				if count % 3 == 0 and (count // 3) % 2 == (if side > 0 then 0 else 1) and onQuay(lamp.Position) then
					local over = -side * frame.RightVector -- toward the water
					Kit.Lamp(model, lamp.Position, math.atan2(-over.X, -over.Z))
				end
				if count % 7 == 3 and side > 0 then
					boat(model, frame * CFrame.new(side * 9.5, 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0), Color3.fromRGB(110 + rng:NextInteger(0, 60), 80, 60))
				end
			end
		end
		x += step
	end
	footbridge(model, -62)
	footbridge(model, 72)
end

-- === The clock tower =========================================================

local function clockTower(parent: Instance, rng: Random)
	local site = Layout.Sites.ClockTower
	local model = Kit.Model("ClockTower", parent)
	local frame = siteFrame(site, 92) -- the tower's centre, facing the plaza
	local half = 8
	local shaft = 64
	Kit.Part({ Name = "Plinth", Size = Vector3.new(19, 4, 19), CFrame = frame * CFrame.new(0, 2, 0), Color = Color3.fromRGB(170, 162, 148), Material = Enum.Material.Slate, Parent = model })
	local body = Kit.Part({ Name = "Shaft", Size = Vector3.new(half * 2, shaft, half * 2), CFrame = frame * CFrame.new(0, shaft / 2, 0), Color = STONE, Material = Enum.Material.Slate, Parent = model })
	poi(body, "ClockTower", "The Clock Tower")
	Kit.Detail({ Name = "Door", Size = Vector3.new(5, 9, 0.6), CFrame = frame * CFrame.new(0, 4.5 + 4, -half - 0.2), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	-- The clock stage, a little wider, a glowing face on every side.
	local stage = shaft + 7
	Kit.Part({ Name = "ClockStage", Size = Vector3.new(19, 14, 19), CFrame = frame * CFrame.new(0, stage, 0), Color = Color3.fromRGB(196, 188, 170), Material = Enum.Material.Slate, Parent = model })
	for k = 0, 3 do
		local face = frame * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, stage, -9.75)
		local dial = Kit.Detail({ Name = "ClockFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 10, 10), CFrame = face * Kit.ALONG_LOOK, Color = P.Cream, Material = Enum.Material.Glass, Parent = model })
		CollectionService:AddTag(dial, Config.Tags.LitWindow) -- glows warm at night
		for _, hand in { { 2.8, -60 }, { 4, 60 } } do
			Kit.Detail({ Name = "Hand", Size = Vector3.new(0.45, hand[1], 0.2), CFrame = face * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, 0, math.rad(hand[2])) * CFrame.new(0, hand[1] / 2 - 0.3, 0), Color = P.Iron, Material = Enum.Material.Metal, Parent = model })
		end
	end
	for _, x in { -1, 1 } do
		Kit.Hanging(model, frame * CFrame.new(x * 4.5, shaft - 4, -half - 0.4), 4, 16, D.HighTown.Color)
	end
	-- The lookout gallery: a floor, four pillars, a roof and the spire.
	local gallery = stage + 7
	Kit.Part({ Name = "Gallery", Size = Vector3.new(21, 1, 21), CFrame = frame * CFrame.new(0, gallery + 0.5, 0), Color = Color3.fromRGB(170, 162, 148), Material = Enum.Material.Slate, Parent = model })
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Kit.Part({ Name = "Pillar", Size = Vector3.new(2.4, 10, 2.4), CFrame = frame * CFrame.new(x * 8.6, gallery + 6, z * 8.6), Color = STONE, Material = Enum.Material.Slate, Parent = model })
		end
	end
	Kit.Part({ Name = "Bell", Shape = Enum.PartType.Ball, Size = Vector3.one * 4, CFrame = frame * CFrame.new(0, gallery + 8, 0), Color = P.Gold, Material = Enum.Material.Metal, Parent = model })
	local y = gallery + 11
	for i, size in { 21, 13, 7, 3 } do
		local height = if i == 1 then 1.4 else 5 + i
		Kit.Part({ Name = "Spire", Size = Vector3.new(size, height, size), CFrame = frame * CFrame.new(0, y + height / 2, 0), Color = if i == 1 then STONE else SLATE, Material = Enum.Material.Slate, Parent = model })
		y += height
	end
	Kit.Rod(model, "Flagpole", (frame * CFrame.new(0, y, 0)).Position, (frame * CFrame.new(0, y + 9, 0)).Position, 0.4, P.Iron, Enum.Material.Metal, true)
	Kit.Pennant(model, (frame * CFrame.new(0, y + 9, 0)).Position, site.Angle + math.rad(90), D.HighTown.Color)
	-- A small square round it: two trees and benches.
	for _, side in { -1, 1 } do
		local spot = frame * CFrame.new(side * 10, 0, -15)
		Kit.Tree(model, spot.Position, rng:NextNumber(16, 20), rng)
		Kit.Part({ Name = "Bench", Size = Vector3.new(1.8, 0.6, 6), CFrame = frame * CFrame.new(side * 12, 1.6, 2), Color = Color3.fromRGB(120, 86, 56), Material = Enum.Material.Wood, Parent = model })
	end
end

-- === The river light =========================================================

local function riverLight(parent: Instance, rng: Random)
	local model = Kit.Model("RiverLight", parent)
	local bank = riverFrame(-95)
	local base = bank * CFrame.new(22, 0, 0)
	local height = 60
	Kit.Part({ Name = "Plinth", Size = Vector3.new(16, 5, 16), CFrame = base * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(160, 152, 136), Material = Enum.Material.Slate, Parent = model })
	local tower = Kit.Part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 12, 12), CFrame = base * CFrame.new(0, height / 2, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(238, 232, 220), Material = Enum.Material.Plaster, Parent = model })
	poi(tower, "RiverLight", "The River Light")
	for _, y in { 22, 44 } do
		Kit.Detail({ Name = "Stripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 12.4, 12.4), CFrame = base * CFrame.new(0, y, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(186, 60, 54), Material = Enum.Material.Plaster, Parent = model })
	end
	Kit.Detail({ Name = "Door", Size = Vector3.new(0.6, 8, 4), CFrame = base * CFrame.new(6, 9, 0), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	for _, y in { 16, 32, 50 } do
		local window = Kit.Detail({ Name = "Window", Size = Vector3.new(0.5, 3, 1.8), CFrame = base * CFrame.new(6, y, 0), Color = P.Glass, Material = Enum.Material.Glass, Parent = model })
		if y == 32 then
			CollectionService:AddTag(window, Config.Tags.LitWindow)
		end
	end
	-- The gallery (a perch all round) and the lantern room.
	Kit.Part({ Name = "Gallery", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 18, 18), CFrame = base * CFrame.new(0, height + 0.6, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(160, 152, 136), Material = Enum.Material.Slate, Parent = model })
	local lantern = Kit.Detail({ Name = "Lantern", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 8, 8), CFrame = base * CFrame.new(0, height + 4.7, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(255, 214, 140), Material = Enum.Material.Glass, Parent = model })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 130)
	light.Range = 50
	light.Brightness = 2
	light.Enabled = false
	light.Parent = lantern
	CollectionService:AddTag(lantern, Config.Tags.NightLight) -- lit at night by each client
	Kit.Part({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 10, 10), CFrame = base * CFrame.new(0, height + 8.8, 0) * Kit.UPRIGHT, Color = SLATE, Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Name = "Top", Size = Vector3.new(5, 4, 5), CFrame = base * CFrame.new(0, height + 11.4, 0), Color = SLATE, Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Name = "Ball", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, CFrame = base * CFrame.new(0, height + 14.4, 0), Color = P.Gold, Material = Enum.Material.Metal, Parent = model })
	-- The dock: a pier into the river and boats tied up to it.
	local pier = riverFrame(-80)
	Kit.Part({ Name = "Pier", Size = Vector3.new(10, 0.8, 5), CFrame = pier * CFrame.new(9, 0.2, 0), Color = Color3.fromRGB(138, 100, 64), Material = Enum.Material.WoodPlanks, Parent = model })
	for _, z in { -2, 2 } do
		Kit.Detail({ Name = "Piling", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 1, 1), CFrame = pier * CFrame.new(4.4, -2.5, z) * Kit.UPRIGHT, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	for i, z in { -6, 6 } do
		boat(model, pier * CFrame.new(7, 0, z * 1.2) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), if i == 1 then Color3.fromRGB(70, 110, 160) else Color3.fromRGB(180, 80, 60))
	end
	Kit.Lamp(model, (pier * CFrame.new(15, 0, -3.5)).Position, math.rad(-90))
end

-- === The water mill ==========================================================

local function waterMill(parent: Instance, rng: Random)
	local model = Kit.Model("WaterMill", parent)
	local bank = riverFrame(90)
	local house = bank * CFrame.new(-21, 0, 0) -- on the north bank
	local width, depth, height = 14, 12, 17
	local body = Kit.Part({ Name = "Body", Size = Vector3.new(depth, height, width), CFrame = house * CFrame.new(0, height / 2, 0), Color = P.Stone[rng:NextInteger(1, #P.Stone)], Material = Enum.Material.Brick, Parent = model })
	poi(body, "WaterMill", "The Water Mill")
	for _, side in { -1, 1 } do
		-- Roof halves, ridge along the river.
		Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(width + 1.2, 7, depth / 2 + 0.6), CFrame = house * CFrame.new(side * (depth / 4 + 0.3), height + 3.5, 0) * CFrame.Angles(0, math.rad(-90) * side, 0), Color = P.Roof[2], Material = Enum.Material.Slate, Parent = model })
	end
	Kit.Detail({ Name = "Door", Size = Vector3.new(3.2, 6.2, 0.5), CFrame = house * CFrame.new(0, 3.1, -width / 2 - 0.1), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	local window = Kit.Detail({ Name = "Window", Size = Vector3.new(0.4, 3.4, 2.2), CFrame = house * CFrame.new(depth / 2 + 0.1, 11, 3), Color = P.Glass, Material = Enum.Material.Glass, Parent = model })
	CollectionService:AddTag(window, Config.Tags.LitWindow)
	-- The wheel, half in the water, and its axle into the wall.
	local hub = bank * CFrame.new(-10.2, 3, 0)
	Kit.Part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 15, 15), CFrame = hub, Color = Color3.fromRGB(112, 80, 52), Material = Enum.Material.Wood, Parent = model })
	for k = 0, 3 do
		Kit.Part({ Name = "Paddle", Size = Vector3.new(2.6, 16.4, 1.1), CFrame = hub * CFrame.Angles(k * math.pi / 4, 0, 0), Color = P.Timber, Material = Enum.Material.WoodPlanks, Parent = model })
	end
	Kit.Detail({ Name = "Axle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 1.2, 1.2), CFrame = hub * CFrame.new(-2.5, 0, 0), Color = P.Iron, Material = Enum.Material.Metal, Parent = model })
	Kit.Cart(model, house * CFrame.new(2, 0, -width / 2 - 6) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(226, 214, 180))
	for i = 1, 3 do
		Kit.Barrel(model, (house * CFrame.new(-depth / 2 - 2, 0, i * 3 - 6)).Position)
	end
end

-- === The great granary =======================================================

local function granary(parent: Instance)
	local site = Layout.Sites.Granary
	local model = Kit.Model("Granary", parent)
	local frame = siteFrame(site, site.Inner + 6) -- front-centre, facing the plaza
	local size, base, height = 22, 14, 50
	local depth = size / 2
	Kit.Part({ Name = "Base", Size = Vector3.new(size, base, size), CFrame = frame * CFrame.new(0, base / 2, depth + 0.6), Color = Color3.fromRGB(164, 156, 142), Material = Enum.Material.Slate, Parent = model })
	local body = Kit.Part({ Name = "Body", Size = Vector3.new(size + 1.2, height - base, size + 1.2), CFrame = frame * CFrame.new(0, base + (height - base) / 2, depth + 0.6), Color = Color3.fromRGB(176, 128, 82), Material = Enum.Material.WoodPlanks, Parent = model })
	poi(body, "Granary", "The Great Granary")
	for _, x in { -1, 1 } do
		Kit.Detail({ Name = "Post", Size = Vector3.new(1.2, height - base, 0.6), CFrame = frame * CFrame.new(x * (size / 2 + 0.3), base + (height - base) / 2, -0.4), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	Kit.Detail({ Name = "BigDoor", Size = Vector3.new(8, 10, 0.5), CFrame = frame * CFrame.new(0, 5, 0.35), Color = P.Door, Material = Enum.Material.WoodPlanks, Parent = model })
	for _, y in { 22, 34 } do
		Kit.Detail({ Name = "LoftDoor", Size = Vector3.new(4, 5, 0.4), CFrame = frame * CFrame.new(0, y, -0.2), Color = P.Door, Material = Enum.Material.WoodPlanks, Parent = model })
	end
	Kit.Hanging(model, frame * CFrame.new(-7, height - 3, -0.4), 4, 13, D.Wallside.Color)
	Kit.Hanging(model, frame * CFrame.new(7, height - 3, -0.4), 4, 13, D.Wallside.Color)
	-- The hoist beam out over the door, and its rope.
	Kit.Part({ Name = "Hoist", Size = Vector3.new(1.2, 1.2, 6), CFrame = frame * CFrame.new(0, height - 2, -2.4), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	Kit.Rod(model, "Rope", (frame * CFrame.new(0, height - 2.6, -5)).Position, (frame * CFrame.new(0, 14, -5)).Position, 0.2, Color3.fromRGB(220, 210, 190), nil, true)
	-- The roof: a flat top with a low wall round it, and supplies.
	local top = frame * CFrame.new(0, height, depth + 0.6)
	Kit.Part({ Name = "Roof", Size = Vector3.new(size + 2, 1, size + 2), CFrame = top * CFrame.new(0, 0.5, 0), Color = SLATE, Material = Enum.Material.Slate, Parent = model })
	for k = 0, 3 do
		Kit.Part({ Name = "Parapet", Size = Vector3.new(size + 2, 1.6, 1), CFrame = top * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 1.8, size / 2 + 0.5), Color = Color3.fromRGB(150, 142, 126), Material = Enum.Material.Slate, Parent = model })
	end
	Kit.SupplyStation(model, (top * CFrame.new(0, 1, 2)).Position, true)
end

function TownLandmarks.Build(parent: Instance, rng: Random)
	clockTower(parent, rng)
	riverLight(parent, rng)
	waterMill(parent, rng)
	granary(parent)
	quays(parent, rng)
end

return TownLandmarks
