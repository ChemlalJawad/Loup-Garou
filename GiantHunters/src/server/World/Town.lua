--!strict
-- The town inside the wall, laid out like the walled districts of the
-- titan-slaying stories: ring roads echoing the wall, avenues running out
-- from a central plaza, and tight rows of tall old houses in between.
--
--   * Row houses: stone ground floor, plaster upper floors jutting out a
--     little, timber frames, windows (some with flower boxes), steep tiled
--     roofs and chimneys, the odd shop sign. Every face is something to hook.
--   * The plaza: a fountain crowned by a statue of the first hunter, trees,
--     lamps and benches.
--   * The church and its bell tower (the tallest perch in town), the
--     hunters' headquarters with the supply depot, the market, a garden,
--     the gate square with its barricades, bridges over the river, washing
--     lines across the alleys, lamps along the avenues.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local Town = {}

local W = Config.World
local P = Kit.Palette

local FLOOR = 8.5

type Band = { Inner: number, Outer: number, MinFloors: number, MaxFloors: number, Warehouses: boolean? }
local BANDS: { Band } = {
	{ Inner = 64, Outer = 112, MinFloors = 4, MaxFloors = 6 },
	{ Inner = 128, Outer = 192, MinFloors = 3, MaxFloors = 6 },
	{ Inner = 208, Outer = 270, MinFloors = 3, MaxFloors = 5, Warehouses = true },
}
local ALLEY = 4

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

-- === Row house ===============================================================
-- `frame`: front-centre at street level, local -Z facing the street.

local function windowRow(model: Model, frame: CFrame, width: number, y: number, z: number, rng: Random, flowers: boolean)
	local count = math.max(1, math.floor((width - 3) / 5.5))
	local spacing = width / count
	for i = 1, count do
		local x = -width / 2 + spacing * (i - 0.5)
		local window = Kit.Detail({ Name = "Window", Size = Vector3.new(2.2, 3.6, 0.4), CFrame = frame * CFrame.new(x, y, z), Color = P.Glass, Material = Enum.Material.Glass, Reflectance = 0.15, Parent = model })
		if rng:NextNumber() < 0.4 then
			CollectionService:AddTag(window, Config.Tags.LitWindow) -- glows warm at night
		end
		Kit.Detail({ Name = "Sill", Size = Vector3.new(3, 0.4, 0.8), CFrame = frame * CFrame.new(x, y - 2, z - 0.2), Color = P.Cream, Material = Enum.Material.SmoothPlastic, Parent = model })
		if flowers and rng:NextNumber() < 0.6 then
			Kit.Detail({
				Name = "Flowers",
				Size = Vector3.new(2.6, 0.8, 0.7),
				CFrame = frame * CFrame.new(x, y - 1.5, z - 0.45),
				Color = pick({ Color3.fromRGB(220, 70, 80), Color3.fromRGB(240, 150, 190), Color3.fromRGB(250, 210, 80) }, rng),
				Material = Enum.Material.Grass,
				Parent = model,
			})
		end
	end
end

local function gableRoof(model: Model, frame: CFrame, width: number, depth: number, centreZ: number, height: number, baseY: number, color: Color3)
	-- Ridge along local X (parallel to the street); a wedge's tall face is
	-- its local +Z, so the front half faces the street as-is and the back
	-- half is turned round.
	for _, side in { -1, 1 } do
		Kit.Part({
			Class = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(width + 1.2, height, depth / 2 + 0.6),
			CFrame = frame * CFrame.new(0, baseY + height / 2, centreZ + side * (depth / 4 + 0.3)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			Color = color,
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
end

local function chimney(model: Model, frame: CFrame, x: number, z: number, top: number, rng: Random)
	local height = 5 + rng:NextNumber(0, 3)
	local stack = Kit.Part({ Name = "Chimney", Size = Vector3.new(2.2, height, 2.2), CFrame = frame * CFrame.new(x, top - height / 2 + 1.5, z), Color = pick(P.Stone, rng), Material = Enum.Material.Brick, Parent = model })
	if rng:NextNumber() < 0.3 then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Color = ColorSequence.new(Color3.fromRGB(205, 205, 210))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 7) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(4, 7)
		smoke.Speed = NumberRange.new(2, 4)
		smoke.Acceleration = Vector3.new(1.5, 1, 0)
		smoke.SpreadAngle = Vector2.new(10, 10)
		smoke.Rate = 1.5
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = stack
	end
end

local function rowHouse(parent: Instance, frame: CFrame, width: number, depth: number, floors: number, rng: Random)
	local model = Kit.Model("House", parent)
	local height = floors * FLOOR
	local plaster = pick(P.Plaster, rng)
	local stone = pick(P.Stone, rng)
	local timbered = rng:NextNumber() < 0.6
	local overhang = if timbered then 0.8 else 0

	-- Stone ground floor, plaster above (jutting out over the street).
	Kit.Part({ Name = "GroundFloor", Size = Vector3.new(width, FLOOR, depth), CFrame = frame * CFrame.new(0, FLOOR / 2, depth / 2), Color = stone, Material = Enum.Material.Slate, Parent = model })
	local upperDepth = depth + overhang
	local upperZ = (depth - overhang) / 2
	Kit.Part({ Name = "Upper", Size = Vector3.new(width, height - FLOOR, upperDepth), CFrame = frame * CFrame.new(0, FLOOR + (height - FLOOR) / 2, upperZ), Color = plaster, Material = Enum.Material.Plaster, Parent = model })

	local face = -overhang - 0.05 -- the upper facade's front plane
	if timbered then
		for f = 1, floors - 1 do
			Kit.Detail({ Name = "Beam", Size = Vector3.new(width + 0.3, 0.6, 0.5), CFrame = frame * CFrame.new(0, f * FLOOR, face - 0.2), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		end
		for _, side in { -1, 1 } do
			Kit.Detail({ Name = "Post", Size = Vector3.new(0.6, height - FLOOR, 0.5), CFrame = frame * CFrame.new(side * (width / 2 - 0.3), FLOOR + (height - FLOOR) / 2, face - 0.2), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
		end
	end
	local flowers = rng:NextNumber() < 0.3
	for f = 1, floors - 1 do
		windowRow(model, frame, width, f * FLOOR + FLOOR * 0.55, face, rng, flowers)
	end

	-- Street level: a door and a shop window or two.
	local doorX = rng:NextNumber(-width / 2 + 2.5, width / 2 - 2.5)
	Kit.Detail({ Name = "Door", Size = Vector3.new(3.2, 6.2, 0.5), CFrame = frame * CFrame.new(doorX, 3.1, -0.1), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	local shopX = if doorX > 0 then doorX - 6 else doorX + 6
	if math.abs(shopX) < width / 2 - 2.5 then
		Kit.Detail({ Name = "ShopWindow", Size = Vector3.new(4.4, 3.6, 0.4), CFrame = frame * CFrame.new(shopX, 3.8, -0.1), Color = P.Glass, Material = Enum.Material.Glass, Reflectance = 0.15, Parent = model })
		if rng:NextNumber() < 0.35 then
			-- A hanging shop sign, out over the street.
			Kit.Detail({ Name = "Sign", Size = Vector3.new(0.3, 2, 3), CFrame = frame * CFrame.new(shopX + 2.6, 7.2, -1.8), Color = pick({ P.HunterBlue, Color3.fromRGB(150, 60, 50), Color3.fromRGB(70, 110, 70) }, rng), Material = Enum.Material.Wood, Parent = model })
		end
	end

	-- Roof: usually steep, sometimes a flat top with a parapet.
	local roofColor = pick(P.Roof, rng)
	if rng:NextNumber() < 0.1 then
		for _, side in { -1, 1 } do
			Kit.Detail({ Name = "Parapet", Size = Vector3.new(width, 1.6, 0.8), CFrame = frame * CFrame.new(0, height + 0.8, upperZ + side * (upperDepth / 2 - 0.4)), Color = plaster, Material = Enum.Material.Plaster, Parent = model })
		end
	else
		local roofHeight = upperDepth * rng:NextNumber(0.34, 0.62)
		gableRoof(model, frame, width, upperDepth, upperZ, roofHeight, height, roofColor)
		if rng:NextNumber() < 0.55 then
			chimney(model, frame, rng:NextNumber(-width / 2 + 2, width / 2 - 2), upperZ + upperDepth * 0.22, height + roofHeight * 0.6, rng)
		end
	end
end

-- Warehouses and stables along the inside of the wall: big, plain, low.
local function warehouse(parent: Instance, frame: CFrame, width: number, depth: number, rng: Random)
	local model = Kit.Model("Warehouse", parent)
	local height = FLOOR * rng:NextInteger(2, 3)
	local wall = pick(P.Stone, rng)
	Kit.Part({ Name = "Body", Size = Vector3.new(width, height, depth), CFrame = frame * CFrame.new(0, height / 2, depth / 2), Color = wall, Material = Enum.Material.Brick, Parent = model })
	Kit.Detail({ Name = "BigDoor", Size = Vector3.new(math.min(8, width - 4), 9, 0.5), CFrame = frame * CFrame.new(0, 4.5, -0.1), Color = P.Door, Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Detail({ Name = "Hayloft", Size = Vector3.new(3, 3, 0.4), CFrame = frame * CFrame.new(0, height - 3.5, -0.1), Color = Color3.fromRGB(40, 36, 34), Parent = model })
	gableRoof(model, frame, width, depth, depth / 2, depth * 0.35, height, pick(P.Roof, rng))
end

-- === Row placement ===========================================================

local function avenueClear(angle: number, radius: number, halfWidth: number): boolean
	for _, degrees in W.AvenueAngles do
		local wide = degrees == 0 or degrees == 180
		local clearance = (if wide then W.AvenueWidth + 6 else W.AvenueWidth) / 2 + halfWidth + 2
		if math.abs(Geo.AngleDelta(angle, math.rad(degrees))) * radius < clearance then
			return false
		end
	end
	return true
end

local function lotClear(frame: CFrame, width: number, depth: number): boolean
	for _, corner in { Vector3.new(-width / 2, 0, 0), Vector3.new(width / 2, 0, 0), Vector3.new(-width / 2, 0, depth), Vector3.new(width / 2, 0, depth), Vector3.new(0, 0, depth / 2) } do
		local p = frame * corner
		if Geo.InRiver(p.X, p.Z, 5) then
			return false
		end
		if Layout.InAnySite(Geo.AngleOf(p), Geo.RadiusOf(p)) then
			return false
		end
	end
	return true
end

local function row(parent: Instance, band: Band, outward: boolean, rng: Random)
	local rowDepth = (band.Outer - band.Inner - ALLEY) / 2
	-- Front edge on the road this row faces; lots measured along the narrower
	-- (inner) edge of the row so neighbours never overlap.
	local front = if outward then band.Outer else band.Inner
	local innerEdge = if outward then band.Outer - rowDepth else band.Inner
	local angle = rng:NextNumber(0, 0.2)
	local stop = angle + math.pi * 2
	while angle < stop do
		local width = rng:NextNumber(13, 21)
		local gap = if rng:NextNumber() < 0.6 then 0.2 else rng:NextNumber(1, 3)
		local step = (width + gap) / innerEdge
		local centre = angle + step / 2
		angle += step
		if centre > stop - step / 2 then
			break
		end
		local depth = rowDepth - rng:NextNumber(0, 3)
		local frame = CFrame.new(Geo.Polar(centre, front)) * CFrame.Angles(0, if outward then centre + math.pi else centre, 0)
		if avenueClear(centre, front, width / 2) and lotClear(frame, width, depth) then
			if rng:NextNumber() < 0.05 then
				-- A little garden instead of a house.
				Kit.Tree(parent, (frame * CFrame.new(0, 0, depth / 2)).Position, rng:NextNumber(16, 24), rng)
			elseif band.Warehouses and outward then
				warehouse(parent, frame, width, depth, rng)
			else
				rowHouse(parent, frame, width, depth, rng:NextInteger(band.MinFloors, band.MaxFloors), rng)
			end
		end
	end
end

-- === Landmarks ===============================================================

local function siteFrame(site: Layout.Site, radius: number): CFrame
	-- Front-centre on `radius`, facing the plaza (local -Z inward).
	return CFrame.new(Geo.Polar(site.Angle, radius)) * CFrame.Angles(0, site.Angle, 0)
end

local function statue(parent: Instance, base: CFrame)
	local model = Kit.Model("HunterStatue", parent)
	local bronze = Color3.fromRGB(96, 128, 108)
	local function bit(name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?)
		Kit.Part({ Name = name, Shape = shape or Enum.PartType.Block, Size = size, CFrame = base * offset, Color = bronze, Material = Enum.Material.Metal, Parent = model })
	end
	bit("Legs", Vector3.new(1.8, 3.2, 1), CFrame.new(0, 1.6, 0))
	bit("Body", Vector3.new(2.2, 2.8, 1.2), CFrame.new(0, 4.6, 0))
	bit("Head", Vector3.new(1.5, 1.5, 1.5), CFrame.new(0, 6.8, 0), Enum.PartType.Ball)
	bit("Cape", Vector3.new(2.6, 4.6, 0.3), CFrame.new(0, 4, 0.75) * CFrame.Angles(math.rad(-12), 0, 0))
	for _, side in { -1, 1 } do
		bit("Arm", Vector3.new(0.7, 2.6, 0.7), CFrame.new(side * 1.5, 6, 0) * CFrame.Angles(0, 0, side * math.rad(-30)))
		bit("Blade", Vector3.new(0.25, 4.4, 0.6), CFrame.new(side * 2.6, 8.6, 0) * CFrame.Angles(0, 0, side * math.rad(-20)))
	end
end

local function plaza(parent: Instance, rng: Random)
	local model = Kit.Model("Plaza", parent)
	local stone = Color3.fromRGB(196, 186, 166)
	-- Fountain: basin, water, column, bowl, and the statue on top.
	Kit.Part({ Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 26, 26), CFrame = CFrame.new(0, 1.3, 0) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Slate, Parent = model })
	local water = Kit.Detail({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 23, 23), CFrame = CFrame.new(0, 2.5, 0) * Kit.UPRIGHT, Color = Color3.fromRGB(90, 150, 170), Material = Enum.Material.Glass, Transparency = 0.25, Parent = model })
	water.CanCollide = false
	Kit.Part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 3.4, 3.4), CFrame = CFrame.new(0, 5, 0) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Slate, Parent = model })
	local bowl = Kit.Part({ Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 10, 10), CFrame = CFrame.new(0, 8.6, 0) * Kit.UPRIGHT, Color = stone, Material = Enum.Material.Slate, Parent = model })
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(210, 235, 245))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.2) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Speed = NumberRange.new(5, 7)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.SpreadAngle = Vector2.new(70, 70)
	spray.Rate = 40
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = bowl
	Kit.Part({ Name = "Plinth", Size = Vector3.new(3, 2, 3), CFrame = CFrame.new(0, 10.2, 0), Color = stone, Material = Enum.Material.Slate, Parent = model })
	statue(model, CFrame.new(0, 11.2, 0) * CFrame.Angles(0, math.pi, 0))

	-- Trees and benches between the avenues, lamps round the edge.
	for _, degrees in W.AvenueAngles do
		local between = math.rad(degrees + 30)
		Kit.Tree(model, Geo.Polar(between, 42), rng:NextNumber(18, 24), rng)
		local bench = CFrame.new(Geo.Polar(between, 32, 0)) * CFrame.Angles(0, between, 0)
		Kit.Part({ Name = "Bench", Size = Vector3.new(6, 0.6, 1.8), CFrame = bench * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(120, 86, 56), Material = Enum.Material.Wood, Parent = model })
		Kit.Detail({ Name = "BenchBack", Size = Vector3.new(6, 1.6, 0.4), CFrame = bench * CFrame.new(0, 2.6, 0.8), Color = Color3.fromRGB(120, 86, 56), Material = Enum.Material.Wood, Parent = model })
		for _, offset in { -12, 12 } do
			local lampAngle = math.rad(degrees + 30) + math.rad(offset)
			Kit.Lamp(model, Geo.Polar(lampAngle, W.PlazaRadius - 3), lampAngle)
		end
	end
	Kit.SupplyStation(model, Vector3.new(0, 0, 30), true)
end

local function church(parent: Instance)
	local site = Layout.Sites.Church
	local model = Kit.Model("Church", parent)
	local frame = siteFrame(site, site.Inner + 2)
	local stone = Color3.fromRGB(206, 198, 182)
	local dark = Color3.fromRGB(150, 142, 128)
	-- Nave behind the tower.
	local naveWidth, naveLength, naveHeight = 26, 30, 30
	local naveZ = 14 + naveLength / 2
	Kit.Part({ Name = "Nave", Size = Vector3.new(naveWidth, naveHeight, naveLength), CFrame = frame * CFrame.new(0, naveHeight / 2, naveZ), Color = stone, Material = Enum.Material.Slate, Parent = model })
	for _, side in { -1, 1 } do
		-- Roof halves (ridge along the nave), buttresses and tall windows.
		Kit.Part({
			Class = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(naveLength + 2, 16, naveWidth / 2 + 1),
			CFrame = frame * CFrame.new(side * (naveWidth / 4 + 0.5), naveHeight + 8, naveZ) * CFrame.Angles(0, math.rad(-90 * side), 0),
			Color = Color3.fromRGB(92, 100, 118),
			Material = Enum.Material.Slate,
			Parent = model,
		})
		for i = 0, 2 do
			local z = 18 + i * 10
			Kit.Part({ Name = "Buttress", Size = Vector3.new(3, naveHeight * 0.7, 3), CFrame = frame * CFrame.new(side * (naveWidth / 2 + 1.5), naveHeight * 0.35, z), Color = dark, Material = Enum.Material.Slate, Parent = model })
			Kit.Detail({ Name = "StainedGlass", Size = Vector3.new(0.4, 12, 3), CFrame = frame * CFrame.new(side * (naveWidth / 2 + 0.1), naveHeight * 0.55, z + 5), Color = if i % 2 == 0 then Color3.fromRGB(70, 90, 160) else Color3.fromRGB(160, 70, 70), Material = Enum.Material.Glass, Parent = model })
		end
	end
	-- The bell tower: shaft, belfry, stepped spire, golden ball.
	local towerSize = 16
	local shaft = 78
	Kit.Part({ Name = "Tower", Size = Vector3.new(towerSize, shaft, towerSize), CFrame = frame * CFrame.new(0, shaft / 2, towerSize / 2), Color = stone, Material = Enum.Material.Slate, Parent = model })
	Kit.Detail({ Name = "Door", Size = Vector3.new(6, 11, 0.6), CFrame = frame * CFrame.new(0, 5.5, -0.2), Color = P.Door, Material = Enum.Material.Wood, Parent = model })
	Kit.Detail({ Name = "RoseWindow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7, 7), CFrame = frame * CFrame.new(0, 18, -0.2) * Kit.ALONG_LOOK, Color = Color3.fromRGB(150, 90, 150), Material = Enum.Material.Glass, Parent = model })
	-- Clock face.
	Kit.Detail({ Name = "Clock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 9, 9), CFrame = frame * CFrame.new(0, shaft - 12, -0.25) * Kit.ALONG_LOOK, Color = P.Cream, Material = Enum.Material.SmoothPlastic, Parent = model })
	Kit.Detail({ Name = "HourHand", Size = Vector3.new(0.5, 2.6, 0.3), CFrame = frame * CFrame.new(0.6, shaft - 11, -0.55) * CFrame.Angles(0, 0, math.rad(-35)), Color = P.Iron, Parent = model })
	Kit.Detail({ Name = "MinuteHand", Size = Vector3.new(0.4, 3.6, 0.3), CFrame = frame * CFrame.new(-0.9, shaft - 11, -0.55) * CFrame.Angles(0, 0, math.rad(40)), Color = P.Iron, Parent = model })
	local belfryY = shaft
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Kit.Part({ Name = "BelfryPillar", Size = Vector3.new(3, 12, 3), CFrame = frame * CFrame.new(x * (towerSize / 2 - 1.5), belfryY + 6, towerSize / 2 + z * (towerSize / 2 - 1.5)), Color = stone, Material = Enum.Material.Slate, Parent = model })
		end
	end
	Kit.Part({ Name = "Bell", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = frame * CFrame.new(0, belfryY + 6, towerSize / 2), Color = P.Gold, Material = Enum.Material.Metal, Parent = model })
	local y = belfryY + 12
	for i, size in { 17, 13, 9, 5 } do
		local height = if i == 4 then 12 else 5
		Kit.Part({ Name = "Spire", Size = Vector3.new(size, height, size), CFrame = frame * CFrame.new(0, y + height / 2, towerSize / 2), Color = if i == 1 then stone else Color3.fromRGB(92, 100, 118), Material = Enum.Material.Slate, Parent = model })
		y += height
	end
	Kit.Part({ Name = "GoldBall", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = frame * CFrame.new(0, y + 1.3, towerSize / 2), Color = P.Gold, Material = Enum.Material.Metal, Parent = model })
end

local function headquarters(parent: Instance)
	local site = Layout.Sites.Depot
	local model = Kit.Model("Headquarters", parent)
	local frame = siteFrame(site, site.Inner + 2)
	local width, depth, height = 44, 34, 30
	local stone = Color3.fromRGB(176, 168, 152)
	Kit.Part({ Name = "Body", Size = Vector3.new(width, height, depth), CFrame = frame * CFrame.new(0, height / 2, depth / 2), Color = stone, Material = Enum.Material.Brick, Parent = model })
	Kit.Detail({ Name = "Gate", Size = Vector3.new(10, 14, 0.6), CFrame = frame * CFrame.new(0, 7, -0.2), Color = P.Door, Material = Enum.Material.WoodPlanks, Parent = model })
	Kit.Detail({ Name = "GateArch", Size = Vector3.new(13, 2, 1.2), CFrame = frame * CFrame.new(0, 14.5, -0.4), Color = Kit.Palette.WallBand, Material = Enum.Material.Slate, Parent = model })
	for _, y in { 11, 21 } do
		for _, x in { -17, -11, 11, 17 } do
			Kit.Detail({ Name = "Window", Size = Vector3.new(3, 4.4, 0.4), CFrame = frame * CFrame.new(x, y, -0.15), Color = P.Glass, Material = Enum.Material.Glass, Parent = model })
		end
	end
	for _, x in { -6, 6 } do
		Kit.Banner(model, frame * CFrame.new(x * 3.2, height - 2, -0.6), 7, 14)
	end
	gableRoof(model, frame, width, depth, depth / 2, 12, height, Color3.fromRGB(92, 100, 118))
	Kit.Rod(model, "Flagpole", (frame * CFrame.new(0, height + 10, depth / 2)).Position, (frame * CFrame.new(0, height + 26, depth / 2)).Position, 0.6, P.Iron, Enum.Material.Metal)
	Kit.Detail({ Name = "Flag", Size = Vector3.new(0.2, 5, 8), CFrame = frame * CFrame.new(0, height + 23.4, depth / 2 + 4.2) * CFrame.Angles(0, math.rad(90), 0), Color = P.HunterBlue, Material = Enum.Material.Fabric, Parent = model })
	-- The supply depot out front: crates and racks of gas canisters.
	for i, x in { -12, 0, 12 } do
		Kit.SupplyStation(model, (frame * CFrame.new(x, 0, -8)).Position, i == 2)
	end
	for _, x in { -19, 19 } do
		for k = 0, 2 do
			Kit.Detail({ Name = "GasCanister", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.6, 1.6), CFrame = frame * CFrame.new(x + k * 1.8 - 1.8, 2, -1.4) * Kit.UPRIGHT, Color = Color3.fromRGB(180, 190, 200), Material = Enum.Material.Metal, Parent = model })
		end
	end
end

local function market(parent: Instance, rng: Random)
	local site = Layout.Sites.Market
	local model = Kit.Model("Market", parent)
	local stripes = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 110, 180), Color3.fromRGB(230, 170, 50), Color3.fromRGB(80, 150, 90) }
	local radius = (site.Inner + site.Outer) / 2
	for row = -1, 1 do
		for column = -1, 1 do
			if row ~= 0 or column ~= 0 then
				local angle = site.Angle + column * site.Spread * 0.6
				local frame = CFrame.new(Geo.Polar(angle, radius + row * 20)) * CFrame.Angles(0, angle + (if row > 0 then math.pi else 0), 0)
				Kit.Part({ Name = "Counter", Size = Vector3.new(8, 3, 3), CFrame = frame * CFrame.new(0, 1.5, 0), Color = Color3.fromRGB(130, 94, 60), Material = Enum.Material.WoodPlanks, Parent = model })
				for _, x in { -3.6, 3.6 } do
					Kit.Detail({ Name = "Pole", Size = Vector3.new(0.5, 8, 0.5), CFrame = frame * CFrame.new(x, 4, 2), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
				end
				Kit.Part({
					Class = "WedgePart",
					Name = "Awning",
					Size = Vector3.new(9, 2.4, 5),
					CFrame = frame * CFrame.new(0, 8.8, -0.2),
					Color = pick(stripes, rng),
					Material = Enum.Material.Fabric,
					Parent = model,
				})
				for g = -1, 1 do
					Kit.Detail({ Name = "Goods", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = frame * CFrame.new(g * 2.4, 3.7, -0.3), Color = pick({ Color3.fromRGB(230, 120, 40), Color3.fromRGB(200, 40, 50), Color3.fromRGB(120, 180, 60), Color3.fromRGB(240, 210, 90) }, rng), Material = Enum.Material.SmoothPlastic, Parent = model })
				end
			end
		end
	end
	-- The well in the middle.
	local centre = Geo.Polar(site.Angle, radius)
	Kit.Part({ Name = "Well", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 7, 7), CFrame = CFrame.new(centre + Vector3.new(0, 1.5, 0)) * Kit.UPRIGHT, Color = Color3.fromRGB(150, 142, 128), Material = Enum.Material.Cobblestone, Parent = model })
	for _, x in { -3, 3 } do
		Kit.Detail({ Name = "WellPost", Size = Vector3.new(0.6, 7, 0.6), CFrame = CFrame.new(centre + Vector3.new(x, 3.5, 0)), Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	end
	Kit.Part({ Class = "WedgePart", Name = "WellRoof", Size = Vector3.new(4, 2, 8), CFrame = CFrame.new(centre + Vector3.new(0, 8, 0)), Color = pick(P.Roof, rng), Material = Enum.Material.Slate, Parent = model })
	Kit.SupplyStation(model, centre + Vector3.new(0, 0, 14), true)
end

local function garden(parent: Instance, rng: Random)
	local site = Layout.Sites.Garden
	local model = Kit.Model("Garden", parent)
	local radius = (site.Inner + site.Outer) / 2
	local centre = Geo.Polar(site.Angle, radius)
	Kit.Part({ Name = "Lawn", Size = Vector3.new(44, 0.4, 56), CFrame = CFrame.new(centre + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, site.Angle, 0), Color = Color3.fromRGB(104, 160, 76), Material = Enum.Material.Grass, Parent = model })
	for _ = 1, 6 do
		local offset = Vector3.new(rng:NextNumber(-16, 16), 0, rng:NextNumber(-22, 22))
		Kit.Tree(model, (CFrame.new(centre) * CFrame.Angles(0, site.Angle, 0) * offset), rng:NextNumber(18, 28), rng)
	end
end

local function gateSquare(parent: Instance, rng: Random)
	local site = Layout.Sites.GateSquare
	local model = Kit.Model("GateSquare", parent)
	-- Barricades (crossed spiked beams) in a loose line across the square.
	for i = -2, 2 do
		local angle = site.Angle + i * 0.09
		local frame = CFrame.new(Geo.Polar(angle, 236 + rng:NextNumber(-6, 6))) * CFrame.Angles(0, angle, 0)
		local barricade = Kit.Model("Barricade", model)
		Kit.Part({ Name = "Rail", Size = Vector3.new(12, 0.8, 0.8), CFrame = frame * CFrame.new(0, 2.4, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = barricade })
		for x = -4, 4, 4 do
			for _, tilt in { -40, 40 } do
				Kit.Part({ Name = "Spike", Size = Vector3.new(0.7, 6, 0.7), CFrame = frame * CFrame.new(x, 2.4, 0) * CFrame.Angles(math.rad(tilt), 0, 0), Color = P.Timber, Material = Enum.Material.Wood, Parent = barricade })
			end
		end
	end
	-- Guardhouse by the gate, with crates.
	local guard = CFrame.new(Geo.Polar(site.Angle - 0.3, 252)) * CFrame.Angles(0, site.Angle - 0.3, 0)
	rowHouse(model, guard, 14, 14, 2, rng)
	Kit.SupplyStation(model, Geo.Polar(site.Angle + 0.22, 246), true)
	for _ = 1, 8 do
		local p = Geo.Polar(site.Angle + rng:NextNumber(-0.35, 0.35), rng:NextNumber(214, 262))
		Kit.Part({ Name = "Crate", Size = Vector3.one * rng:NextNumber(2.5, 4), CFrame = CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(150, 112, 70), Material = Enum.Material.WoodPlanks, Parent = model })
	end
end

-- Stone bridges wherever a road crosses the river.
local function bridges(parent: Instance)
	local paths: { { Vector3 } } = {}
	for _, degrees in W.AvenueAngles do
		local samples = {}
		-- Avenues stop short of the perimeter road, which has its own bridges.
		for r = W.PlazaRadius, W.PerimeterRoad - 20, 1 do
			table.insert(samples, Geo.Polar(math.rad(degrees), r))
		end
		table.insert(paths, samples)
	end
	for _, radius in { W.RingRoads[1], W.RingRoads[2], (W.PerimeterRoad + W.WallRadius) / 2 } do
		local samples = {}
		for i = 0, 1440 do
			table.insert(samples, Geo.Polar(i / 1440 * math.pi * 2, radius))
		end
		table.insert(paths, samples)
	end
	for _, samples in paths do
		local first: Vector3? = nil
		local last: Vector3? = nil
		local function build()
			if first and last then
				local a, b = first :: Vector3, last :: Vector3
				local along = (b - a).Unit
				a -= along * 7
				b += along * 7
				local model = Kit.Model("Bridge", parent)
				local frame = CFrame.lookAt((a + b) / 2, b)
				local length = (b - a).Magnitude
				Kit.Part({ Name = "Deck", Size = Vector3.new(14, 1.6, length), CFrame = frame * CFrame.new(0, -0.2, 0), Color = Color3.fromRGB(170, 160, 144), Material = Enum.Material.Cobblestone, Parent = model })
				for _, side in { -1, 1 } do
					Kit.Part({ Name = "Parapet", Size = Vector3.new(1, 2, length), CFrame = frame * CFrame.new(side * 7.5, 1.6, 0), Color = Color3.fromRGB(150, 142, 128), Material = Enum.Material.Slate, Parent = model })
					Kit.Lamp(model, (frame * CFrame.new(side * 7.5, 2.6, -length / 2 + 1)).Position, 0)
				end
				for _, t in { -0.18, 0.18 } do
					Kit.Part({ Name = "Pier", Size = Vector3.new(12, 12, 3), CFrame = frame * CFrame.new(0, -7, t * length), Color = Color3.fromRGB(140, 132, 118), Material = Enum.Material.Slate, Parent = model })
				end
			end
			first, last = nil, nil
		end
		for _, p in samples do
			if Geo.InRiver(p.X, p.Z, 3) then
				first = first or p
				last = p
			elseif first then
				build()
			end
		end
		build()
	end
end

-- Washing lines strung across alleys: a rope and a few bright cloths.
local function washingLines(parent: Instance, rng: Random)
	local colors = { Color3.fromRGB(240, 240, 235), Color3.fromRGB(200, 80, 80), Color3.fromRGB(90, 130, 200), Color3.fromRGB(240, 200, 90) }
	for _ = 1, 44 do
		local band = BANDS[rng:NextInteger(1, #BANDS)]
		local middle = (band.Inner + band.Outer) / 2
		local angle = rng:NextNumber(0, math.pi * 2)
		if avenueClear(angle, middle, 4) and not Layout.InAnySite(angle, middle) then
			local y = rng:NextNumber(12, 20)
			local a = Geo.Polar(angle, middle - ALLEY / 2 - 1, y)
			local b = Geo.Polar(angle, middle + ALLEY / 2 + 1, y)
			if not Geo.InRiver(a.X, a.Z, 6) then
				local model = Kit.Model("WashingLine", parent)
				local rope = Kit.Rod(model, "Rope", a, b, 0.15, Color3.fromRGB(220, 210, 190))
				rope.CastShadow = false
				local across = Vector3.new(math.cos(angle), 0, -math.sin(angle))
				for i = 1, 2 do
					local t = i / 3
					Kit.Detail({
						Name = "Cloth",
						Size = Vector3.new(1.6, 2.2, 0.1),
						CFrame = CFrame.lookAt(a:Lerp(b, t) - Vector3.new(0, 1.1, 0), a:Lerp(b, t) - Vector3.new(0, 1.1, 0) + across),
						Color = pick(colors, rng),
						Material = Enum.Material.Fabric,
						Parent = model,
					})
				end
			end
		end
	end
end

-- Lamps round the ring roads (the avenues have their own).
local function ringLamps(parent: Instance)
	for _, radius in W.RingRoads do
		local count = math.floor(radius * math.pi * 2 / 42)
		for i = 1, count do
			local angle = i / count * math.pi * 2
			for _, side in { -1, 1 } do
				local r = radius + side * (W.RoadWidth / 2 - 1.2)
				local p = Geo.Polar(angle, r)
				if avenueClear(angle, r, 3) and not Geo.InRiver(p.X, p.Z, 4) and not Layout.InAnySite(angle, r) then
					Kit.Lamp(parent, p, angle + (if side > 0 then 0 else math.pi))
				end
			end
		end
	end
end

-- Torches round the plaza and the gate square.
local function torches(parent: Instance)
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2 + math.rad(15)
		Kit.Torch(parent, CFrame.new(Geo.Polar(angle, W.PlazaRadius + 2)))
	end
	for i = -3, 3 do
		Kit.Torch(parent, CFrame.new(Geo.Polar(i * 0.12, 214)))
	end
end

-- Lamps along the avenues.
local function avenueLamps(parent: Instance)
	for _, degrees in W.AvenueAngles do
		local angle = math.rad(degrees)
		local halfWidth = (if degrees == 0 or degrees == 180 then W.AvenueWidth + 6 else W.AvenueWidth) / 2
		for r = 80, 260, 45 do
			for _, side in { -1, 1 } do
				local across = Vector3.new(math.cos(angle), 0, -math.sin(angle)) * side * (halfWidth - 1.5)
				local p = Geo.Polar(angle, r) + across
				if not Geo.InRiver(p.X, p.Z, 4) then
					Kit.Lamp(parent, p, angle + (if side > 0 then math.rad(90) else math.rad(-90)))
				end
			end
		end
	end
end

function Town.Build(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Town"
	folder.Parent = parent
	for _, band in BANDS do
		row(folder, band, false, rng)
		row(folder, band, true, rng)
	end
	plaza(folder, rng)
	church(folder)
	headquarters(folder)
	market(folder, rng)
	garden(folder, rng)
	gateSquare(folder, rng)
	bridges(folder)
	washingLines(folder, rng)
	avenueLamps(folder)
	ringLamps(folder)
	torches(folder)
end

return Town
