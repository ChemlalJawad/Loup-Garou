--!strict
-- Landmark set pieces out in the wilds: things you can see from far off to
-- find your way, and good lines to swing along (Layout says where):
--
--   * The old mill tower (far north-west): a broken stone tower, its top
--     fallen in, one sail spar still hanging off it and another lying in
--     the grass. A supply crate on the floor inside the broken top.
--   * The aqueduct (north-east plains): tall stone piers carrying a water
--     channel across the grass and over the north road, with a few spans
--     fallen. Hook pier to pier, or run along the top. A crate halfway.
--   * The watch-fort (where the east road enters the Great Forest): a log
--     stockade with a gate on the road, a lookout tower with a crate on its
--     deck, a banner and a torch.
--
-- Wilds builds these early (before the forests and the towers), passing in
-- its spacing and hook-coverage helpers, so everything else keeps clear.

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local Landmarks = {}

export type Helpers = {
	Occupy: (Vector3, number) -> (),
	Free: (Vector3, number) -> boolean,
	AddAnchor: (Vector3) -> (),
	Supplies: (Instance, Vector3, boolean) -> (),
	Grounded: (Vector3, number?) -> Vector3,
	ClearSpot: (Vector3, number) -> boolean,
	-- A giant tree (World/Wilds): (parent, base, height, rng, deckY?) -> (model, trunk width).
	GiantTree: (Instance, Vector3, number, Random, number?) -> (Model, number),
	-- Marks a named place to discover: (PoiId, PoiName, where, radius).
	Poi: (string, string, Vector3, number) -> (),
}

local P = Kit.Palette
local STONE = Color3.fromRGB(168, 160, 146)
local DARK_STONE = Color3.fromRGB(128, 122, 112)
local MOSS = Color3.fromRGB(96, 122, 72)
local LOGS = Color3.fromRGB(112, 82, 56)

-- === The old mill tower =======================================================

local function millRuin(parent: Instance, h: Helpers, rng: Random)
	local at = h.Grounded(Layout.MillRuin, 2)
	local model = Kit.Model("MillRuin", parent)
	local base = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local height, width = 58, 18
	Kit.Part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, width, width), CFrame = base * CFrame.new(0, height / 2, 0) * Kit.UPRIGHT, Color = STONE, Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Name = "Footing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, width + 4, width + 4), CFrame = base * CFrame.new(0, 3, 0) * Kit.UPRIGHT, Color = DARK_STONE, Material = Enum.Material.Cobblestone, Parent = model })
	-- The broken top: jagged stubs of wall round a floor you can land on.
	for i, rise in { 9, 4, 12, 2, 7 } do
		local turn = i / 5 * math.pi * 2
		Kit.Part({ Name = "BrokenWall", Size = Vector3.new(7, rise, 3), CFrame = base * CFrame.Angles(0, turn, 0) * CFrame.new(0, height + rise / 2, -width / 2 + 1.5), Color = STONE, Material = Enum.Material.Slate, Parent = model })
	end
	Kit.Part({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, width - 3, width - 3), CFrame = base * CFrame.new(0, height + 0.5, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(120, 92, 64), Material = Enum.Material.WoodPlanks, Parent = model })
	h.Supplies(model, (base * CFrame.new(0, height + 1, 0)).Position, true)
	-- Moss creeping up one side, dark window slits.
	Kit.Detail({ Name = "Moss", Size = Vector3.new(8, 20, 1), CFrame = base * CFrame.Angles(0, 2.2, 0) * CFrame.new(0, 10, -width / 2 - 0.1), Color = MOSS, Material = Enum.Material.Grass, Parent = model })
	for _, y in { 16, 32, 46 } do
		Kit.Detail({ Name = "Window", Size = Vector3.new(2.4, 4.5, 0.6), CFrame = base * CFrame.Angles(0, y * 0.05, 0) * CFrame.new(0, y, -width / 2 - 0.05), Color = Color3.fromRGB(40, 34, 30), Parent = model })
	end
	-- One sail spar still hanging off the hub, the other fallen in the grass.
	local hub = base * CFrame.new(0, height - 8, -width / 2 - 1.5)
	Kit.Part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3), CFrame = hub * Kit.ALONG_LOOK, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	local hanging = hub * CFrame.Angles(0, 0, math.rad(145)) * CFrame.new(0, 11, -1)
	Kit.Part({ Name = "Spar", Size = Vector3.new(1.2, 22, 1), CFrame = hanging, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	Kit.Detail({ Name = "Sail", Size = Vector3.new(5, 14, 0.3), CFrame = hanging * CFrame.new(3, 1, -0.2) * CFrame.Angles(0, 0, 0.06), Color = Color3.fromRGB(200, 190, 168), Material = Enum.Material.Fabric, Parent = model })
	local fallen = base * CFrame.new(16, 1.2, -18) * CFrame.Angles(0, 0.7, 0) * CFrame.Angles(math.rad(84), 0, 0)
	Kit.Part({ Name = "FallenSpar", Size = Vector3.new(1.2, 30, 1), CFrame = fallen, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	for k = 1, 4 do
		local spot = base * CFrame.Angles(0, k * 1.4, 0) * CFrame.new(0, 1, -width / 2 - 4 - k)
		Kit.Part({ Name = "Rubble", Size = Vector3.new(3 + k % 2 * 2, 2 + k % 3, 3), CFrame = spot * CFrame.Angles(0.3 * k, 0.6 * k, 0.2), Color = STONE, Material = Enum.Material.Slate, Parent = model })
	end
	h.AddAnchor(at)
	h.Occupy(at, width / 2 + 12)
	h.Poi("MillRuin", "Old Mill Tower", at, 60)
end

-- === The aqueduct =============================================================

local function aqueduct(parent: Instance, h: Helpers, rng: Random)
	local spec = Layout.Aqueduct
	local folder = Instance.new("Folder")
	folder.Name = "Aqueduct"
	folder.Parent = parent
	local from, to = spec.From, spec.To
	local length = (to - from).Magnitude
	local along = (to - from).Unit
	local height = spec.Height
	local SPACING = 42
	local count = math.floor(length / SPACING)
	-- Piers wherever the ground is clear (none on the road).
	type Pier = { At: Vector3, Top: number, Index: number }
	local piers: { Pier } = {}
	-- One pier crumbled to a stump, and two other spans fallen.
	local stumpAt = rng:NextInteger(3, count - 3)
	local fallen = { [rng:NextInteger(1, stumpAt - 2)] = true, [rng:NextInteger(stumpAt + 2, count - 1)] = true }
	for i = 0, count do
		local p = from + along * (i * SPACING)
		if h.ClearSpot(p, 6) and h.Free(p, 6) then
			local stump = i == stumpAt
			table.insert(piers, { At = h.Grounded(p, 3), Top = if stump then rng:NextNumber(18, 30) else height, Index = i })
		end
	end
	-- Keep the whole line clear (trees and towers go elsewhere).
	for d = 0, length, 14 do
		h.Occupy(from + along * d, 24) -- (giant trees spread wide)
	end
	h.Poi("Aqueduct", "The Aqueduct", (from + to) / 2, length / 2)
	local frame = CFrame.lookAt(Vector3.zero, along)
	local crateDone = false
	for k, pier in piers do
		local model = Kit.Model("AqueductPier", folder)
		local base = frame + pier.At
		local tall = pier.Top + 3
		Kit.Part({ Name = "Pier", Size = Vector3.new(10, tall, 7), CFrame = base * CFrame.new(0, tall / 2, 0), Color = STONE, Material = Enum.Material.Slate, Parent = model })
		Kit.Part({ Name = "Plinth", Size = Vector3.new(12, 4, 9), CFrame = base * CFrame.new(0, 2, 0), Color = DARK_STONE, Material = Enum.Material.Cobblestone, Parent = model })
		if pier.Top >= height then
			Kit.Part({ Name = "Capital", Size = Vector3.new(12, 2, 9), CFrame = base * CFrame.new(0, tall - 1, 0), Color = DARK_STONE, Material = Enum.Material.Slate, Parent = model })
		else
			Kit.Part({ Name = "Rubble", Size = Vector3.new(6, 3, 5), CFrame = base * CFrame.new(5, 1.5, 6) * CFrame.Angles(0.3, 0.8, 0.2), Color = STONE, Material = Enum.Material.Slate, Parent = model })
		end
		h.AddAnchor(pier.At)
		h.Occupy(pier.At, 8)
		-- The span to the next pier: an arch beam and the channel on top. A
		-- few have fallen; spans over the road are longer (one pier skipped).
		local nextPier = piers[k + 1]
		if nextPier and pier.Top >= height and nextPier.Top >= height and nextPier.Index - pier.Index <= 2 and not fallen[pier.Index] then
			local a, b = pier.At + Vector3.new(0, height, 0), nextPier.At + Vector3.new(0, height, 0)
			local span = (b - a).Magnitude
			local mid = CFrame.lookAt((a + b) / 2, b)
			local spanModel = Kit.Model("AqueductSpan", folder)
			Kit.Part({ Name = "Arch", Size = Vector3.new(8, 6, span), CFrame = mid * CFrame.new(0, 0, 0), Color = STONE, Material = Enum.Material.Slate, Parent = spanModel })
			Kit.Part({ Name = "Channel", Size = Vector3.new(10, 1, span), CFrame = mid * CFrame.new(0, 3.5, 0), Color = DARK_STONE, Material = Enum.Material.Slate, Parent = spanModel })
			for _, side in { -1, 1 } do
				Kit.Part({ Name = "ChannelWall", Size = Vector3.new(1.4, 3, span), CFrame = mid * CFrame.new(side * 4.3, 5, 0), Color = STONE, Material = Enum.Material.Slate, Parent = spanModel })
			end
			Kit.Detail({ Name = "Water", Size = Vector3.new(7, 0.6, span), CFrame = mid * CFrame.new(0, 4.2, 0), Color = Color3.fromRGB(96, 150, 170), Material = Enum.Material.Glass, Transparency = 0.3, Parent = spanModel })
			if not crateDone and k >= #piers / 2 then
				crateDone = true
				h.Supplies(spanModel, (mid * CFrame.new(0, 4.5, 0)).Position, true)
			end
		end
	end
end

-- === The watch-fort ===========================================================

local function watchFort(parent: Instance, h: Helpers)
	-- Beside the east road's last leg, as it enters the Great Forest.
	local road = Layout.Roads[2]
	local a, b = road[#road - 1], road[#road]
	local along = (b - a).Unit
	local onRoad = a + (b - a) * Layout.WatchFortRoad
	local half = 18
	local centre: Vector3? = nil
	local facing = Vector3.zero
	for _, side in { 1, -1 } do
		local out = Vector3.new(along.Z, 0, -along.X) * side
		local p = onRoad + out * (Layout.RoadHalfWidth + half + 3)
		if h.ClearSpot(p, half - 4) and h.Free(p, half) then
			centre, facing = p, -out
			break
		end
	end
	if not centre then
		return
	end
	local at = h.Grounded(centre :: Vector3)
	local model = Kit.Model("WatchFort", parent)
	local base = CFrame.lookAt(at, at + facing) -- local -Z faces the road
	-- The stockade: log walls, a gate gap on the road side.
	local wallHeight = 12
	for i = 0, 3 do
		local side = base * CFrame.Angles(0, i * math.pi / 2, 0)
		if i == 0 then
			for _, x in { -1, 1 } do
				Kit.Part({ Name = "Stockade", Size = Vector3.new(half - 5, wallHeight, 2.4), CFrame = side * CFrame.new(x * (half / 2 + 2.5), wallHeight / 2, -half), Color = LOGS, Material = Enum.Material.Wood, Parent = model })
				Kit.Part({ Name = "GatePost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(wallHeight + 4, 2.6, 2.6), CFrame = side * CFrame.new(x * 5, (wallHeight + 4) / 2, -half) * Kit.UPRIGHT, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
			end
			Kit.Banner(model, side * CFrame.new(-(half / 2 + 2.5), wallHeight - 0.5, -half - 1.4), 5, 8)
		else
			Kit.Part({ Name = "Stockade", Size = Vector3.new(half * 2, wallHeight, 2.4), CFrame = side * CFrame.new(0, wallHeight / 2, -half), Color = LOGS, Material = Enum.Material.Wood, Parent = model })
		end
	end
	-- The lookout tower in the back corner: four posts, a deck, a roof.
	local towerAt = base * CFrame.new(half - 7, 0, half - 7)
	local deckY, top = 48, 4
	for _, c in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) } do
		Kit.Rod(model, "Post", (towerAt * CFrame.new(c * 5)).Position, (towerAt * CFrame.new(c * top + Vector3.new(0, deckY + 8, 0))).Position, 1.4, P.Timber, Enum.Material.Wood)
	end
	Kit.Part({ Name = "Deck", Size = Vector3.new(top * 2 + 5, 1, top * 2 + 5), CFrame = towerAt * CFrame.new(0, deckY + 0.5, 0), Color = Color3.fromRGB(140, 104, 66), Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Part({ Name = "Rail", Size = Vector3.new(top * 2 + 5, 2.5, 0.6), CFrame = towerAt * CFrame.new(0, deckY + 2.25, -(top + 2.2)), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	for _, turn in { 0, math.pi } do
		Kit.Part({ Class = "WedgePart", Name = "Roof", Size = Vector3.new(top * 2 + 6, 4, top + 3), CFrame = towerAt * CFrame.Angles(0, turn, 0) * CFrame.new(0, deckY + 10, -(top + 3) / 2), Color = P.Roof[2], Material = Enum.Material.Slate, Parent = model })
	end
	h.Supplies(model, (towerAt * CFrame.new(0, deckY + 1, 1)).Position, true)
	Kit.Torch(model, towerAt * CFrame.new(-top, deckY + 1, top))
	-- A tent and a woodpile in the yard.
	Kit.Part({ Class = "WedgePart", Name = "Tent", Size = Vector3.new(8, 6, 5), CFrame = base * CFrame.new(-7, 3, 4), Color = Color3.fromRGB(216, 204, 176), Material = Enum.Material.Fabric, Parent = model })
	Kit.Part({ Class = "WedgePart", Name = "Tent", Size = Vector3.new(8, 6, 5), CFrame = base * CFrame.new(-7, 3, 9) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(216, 204, 176), Material = Enum.Material.Fabric, Parent = model })
	for k = 0, 2 do
		Kit.Part({ Name = "Logs", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 1.6, 1.6), CFrame = base * CFrame.new(-10 + k * 1.7, 0.8 + (k % 2) * 1.2, -8) * CFrame.Angles(0, math.rad(90), 0), Color = LOGS, Material = Enum.Material.Wood, Parent = model })
	end
	h.AddAnchor(at)
	h.Occupy(at, half + 2)
	h.Poi("WatchFort", "Watch-Fort", at, 50)
end

function Landmarks.Build(parent: Instance, rng: Random, helpers: Helpers)
	local folder = Instance.new("Folder")
	folder.Name = "Landmarks"
	folder.Parent = parent
	millRuin(folder, helpers, rng)
	aqueduct(folder, helpers, rng)
	watchFort(folder, helpers)
end

return Landmarks
