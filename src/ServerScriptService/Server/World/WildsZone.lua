--!strict
-- Themed wild areas, so the open ground between zones is somewhere to
-- explore instead of an empty lawn:
--
--   * Candy Land    - pink sugar ground, giant lollipops, candy canes,
--                     gumdrops and cotton-candy trees along the Fun Park path.
--   * Crystal Grove - dark violet ground with glowing crystal clusters, north
--                     of the Lily Pond.
--   * Tulip Fields  - rows of tulips on dirt ridges with a spinning windmill,
--                     along the southern strip.
--   * Rock outcrops - boulders half-buried in the grass across the map.
--   * Backdrops     - a smoking volcano beyond the south edge and snowy
--                     mountains behind the Arena: seen, never reached.
--
-- Order 160: after TerrainZone (terrain exists) and BiomeZone (the pond,
-- statues and hill band are already in PathRegistry, so nothing here lands
-- on them), before LandscapeZone (200), which then keeps its trees out of the
-- rects registered here. Every terrain feature is skipped if TerrainZone
-- failed; the props still go in.
--
-- Cost: ~200 candy parts, ~80 crystal parts, ~470 tulips (one part each),
-- ~15 windmill parts, ~25 volcano parts. Nearly all non-colliding,
-- non-queryable and shadowless.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)
local PathRegistry = require(script.Parent.PathRegistry)

local WildsZone = {}
WildsZone.Order = 160

local SEED = 20261002
local SURFACE_Y = WorldLayout.GroundY - 0.05

type Rect = { Center: Vector3, Size: Vector3 }

local function useTerrain(): boolean
	return Workspace.Terrain:GetAttribute("HatchWarsTerrain") == true
end

local function paintGround(rect: Rect, material: Enum.Material)
	Workspace.Terrain:FillBlock(
		CFrame.new(rect.Center.X, SURFACE_Y - 2, rect.Center.Z),
		Vector3.new(rect.Size.X, 4, rect.Size.Z),
		material
	)
end

-- Non-colliding, non-queryable, shadowless: pure scenery.
local function decor(props: WorldKit.PartProps): Part
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	props.CanTouch = false
	props.CastShadow = false
	return WorldKit.Part(props)
end

local function ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	return decor({
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		Position = position,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

-- Random spots inside `rect` that are clear of every registered path /
-- keep-out and at least `spacing` from each other.
local function scatter(rng: Random, rect: Rect, count: number, spacing: number, margin: number): { Vector3 }
	local spots: { Vector3 } = {}
	local halfX, halfZ = rect.Size.X / 2 - margin, rect.Size.Z / 2 - margin
	for _ = 1, count * 30 do
		if #spots >= count then
			break
		end
		local spot = Vector3.new(
			rect.Center.X + rng:NextNumber(-halfX, halfX),
			WorldLayout.GroundY,
			rect.Center.Z + rng:NextNumber(-halfZ, halfZ)
		)
		if not PathRegistry.IsNearPath(spot, margin) then
			local ok = true
			for _, other in spots do
				if (other - spot).Magnitude < spacing then
					ok = false
					break
				end
			end
			if ok then
				table.insert(spots, spot)
			end
		end
	end
	return spots
end

local function areaSign(parent: Instance, position: Vector3, text: string, color: Color3)
	local post = decor({
		Name = "SignPost",
		Size = Vector3.new(0.8, 6, 0.8),
		Position = position + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(120, 82, 52),
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = parent,
	})
	WorldKit.Sign({
		Name = "AreaSign",
		Adornee = post,
		Text = text,
		Color = color,
		Size = UDim2.new(0, 280, 0, 48),
		TextSize = 26,
		StudsOffset = Vector3.new(0, 5, 0),
		MaxDistance = 180,
	})
end

-- === Candy Land ==============================================================

local CANDY_COLORS = {
	Color3.fromRGB(255, 105, 150),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(120, 230, 150),
	Color3.fromRGB(255, 150, 80),
}

local function lollipop(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(7, 11)
	local diameter = rng:NextNumber(4.5, 6.5)
	local yaw = rng:NextNumber(0, math.pi * 2)
	decor({
		Name = "Stick",
		Size = Vector3.new(0.5, height, 0.5),
		Position = base + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(250, 248, 240),
		CanCollide = true,
		Parent = parent,
	})
	-- A candy disc: flat cylinder standing upright, with rings for the swirl.
	local centre = CFrame.new(base + Vector3.new(0, height + diameter / 2 - 0.5, 0)) * CFrame.Angles(0, yaw, 0)
	local a, b = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)], Color3.fromRGB(255, 255, 255)
	for i, scale in { 1, 0.72, 0.46, 0.2 } do
		decor({
			Name = `Swirl{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6 + i * 0.04, diameter * scale, diameter * scale),
			CFrame = centre * CFrame.Angles(0, math.pi / 2, 0),
			Color = if i % 2 == 1 then a else b,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.1,
			Parent = parent,
		})
	end
end

local function candyCane(parent: Instance, base: Vector3, rng: Random)
	local segments = 8
	local height = 1.1
	local tilt = CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.08, 0.08))
	for i = 0, segments - 1 do
		decor({
			Name = `Stripe{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 1.1, 1.1),
			CFrame = CFrame.new(base) * tilt * CFrame.new(0, height * (i + 0.5), 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i % 2 == 0 then Color3.fromRGB(230, 40, 60) else Color3.fromRGB(250, 250, 250),
			CanCollide = i == 0,
			Parent = parent,
		})
	end
	-- The hook: a ball and a short sideways piece.
	local top = CFrame.new(base) * tilt * CFrame.new(0, height * segments, 0)
	ball(parent, (top * CFrame.new(0.6, 0.3, 0)).Position, 1.2, Color3.fromRGB(230, 40, 60))
	decor({
		Name = "Hook",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 1.1, 1.1),
		CFrame = top * CFrame.new(1.3, 0.3, 0),
		Color = Color3.fromRGB(250, 250, 250),
		Parent = parent,
	})
end

local function gumdrop(parent: Instance, base: Vector3, rng: Random)
	local size = rng:NextNumber(2.5, 4.5)
	decor({
		Name = "Gumdrop",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Position = base + Vector3.new(0, size * 0.2, 0),
		Color = CANDY_COLORS[rng:NextInteger(1, #CANDY_COLORS)],
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		CanCollide = true, -- bouncy-looking things you can hop on
		Parent = parent,
	})
end

local function cottonCandyTree(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(6, 9)
	decor({
		Name = "Cone",
		Size = Vector3.new(0.7, height, 0.7),
		Position = base + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(245, 235, 210),
		CanCollide = true,
		Parent = parent,
	})
	local fluff = if rng:NextNumber() < 0.5 then Color3.fromRGB(255, 170, 210) else Color3.fromRGB(160, 210, 255)
	for i, offset in { Vector3.new(0, 0, 0), Vector3.new(1.4, -0.6, 0.6), Vector3.new(-1.2, -0.4, -0.8), Vector3.new(0.2, 1.1, -0.3) } do
		local puff = ball(parent, base + Vector3.new(0, height + 1.5, 0) + offset, rng:NextNumber(3.2, 4.4), fluff)
		puff.Name = `Fluff{i}`
		puff.Material = Enum.Material.Fabric
	end
end

local function buildCandyLand(parent: Instance, rng: Random)
	local rect = WorldLayout.Wilds.CandyLand :: Rect
	local folder = WorldKit.Group("CandyLand", parent)
	if useTerrain() then
		Workspace.Terrain:SetMaterialColor(Enum.Material.Salt, Color3.fromRGB(255, 196, 222))
		paintGround(rect, Enum.Material.Salt)
	end
	local builders = { lollipop, lollipop, candyCane, candyCane, gumdrop, gumdrop, gumdrop, cottonCandyTree }
	for i, spot in scatter(rng, rect, 46, 8, 5) do
		local prop = WorldKit.PropModel(`Candy{i}`, folder)
		builders[rng:NextInteger(1, #builders)](prop, spot, rng)
	end
	areaSign(folder, rect.Center + Vector3.new(-14, 0, -rect.Size.Z / 2 + 4), "CANDY LAND", Color3.fromRGB(255, 150, 200))
end

-- === Crystal Grove ===========================================================

local CRYSTAL_COLORS = {
	Color3.fromRGB(120, 230, 255),
	Color3.fromRGB(210, 120, 255),
	Color3.fromRGB(255, 120, 210),
	Color3.fromRGB(140, 160, 255),
}

local function crystalCluster(parent: Instance, base: Vector3, rng: Random, withLight: boolean)
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local count = rng:NextInteger(3, 5)
	local tallest: Part? = nil
	for i = 1, count do
		local height = if i == 1 then rng:NextNumber(6, 10) else rng:NextNumber(2.5, 6)
		local width = height * 0.28
		local lean = CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.45, 0.45))
		local offset = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-1.6, 1.6), 0, rng:NextNumber(-1.6, 1.6))
		local shard = decor({
			Name = `Shard{i}`,
			Size = Vector3.new(width, height, width),
			CFrame = CFrame.new(base + offset) * lean * CFrame.new(0, height / 2 - 0.3, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			Reflectance = 0.2,
			CanCollide = i == 1,
			Parent = parent,
		})
		-- A glowing core inside the big shard.
		if i == 1 then
			tallest = shard
			decor({
				Name = "Core",
				Size = Vector3.new(width * 0.4, height * 0.8, width * 0.4),
				CFrame = shard.CFrame,
				Color = color,
				Material = Enum.Material.Neon,
				Parent = parent,
			})
		end
	end
	if withLight and tallest then
		WorldKit.Light({ Name = "CrystalGlow", Color = color, Brightness = 2, Range = 16, Parent = tallest })
	end
end

local function buildCrystalGrove(parent: Instance, rng: Random)
	local rect = WorldLayout.Wilds.CrystalGrove :: Rect
	local folder = WorldKit.Group("CrystalGrove", parent)
	if useTerrain() then
		Workspace.Terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(78, 66, 110))
		paintGround(rect, Enum.Material.Slate)
	end
	for i, spot in scatter(rng, rect, 16, 7, 4) do
		local prop = WorldKit.PropModel(`Crystals{i}`, folder)
		-- Only every third cluster carries a light: plenty of glow at night,
		-- a fraction of the lighting cost.
		crystalCluster(prop, spot, rng, i % 3 == 1)
	end
	-- Sparkles drifting over the grove (decor: off on low graphics).
	local anchor = decor({
		Name = "Sparkles",
		Size = rect.Size + Vector3.new(0, 6, 0),
		Position = rect.Center + Vector3.new(0, 4, 0),
		Transparency = 1,
		Parent = folder,
	})
	WorldKit.Emitter({
		Name = "Sparkles",
		Color = Color3.fromRGB(220, 200, 255),
		Rate = 10,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(0.2, 1),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Parent = anchor,
	})
	areaSign(folder, rect.Center + Vector3.new(0, 0, -rect.Size.Z / 2 + 3), "CRYSTAL GROVE", Color3.fromRGB(200, 170, 255))
end

-- === Tulip Fields + windmill =================================================

local TULIP_COLORS = {
	Color3.fromRGB(240, 60, 80),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(250, 140, 200),
	Color3.fromRGB(255, 140, 50),
	Color3.fromRGB(180, 110, 240),
	Color3.fromRGB(250, 250, 250),
}

local function windmill(parent: Instance, base: Vector3)
	local model = WorldKit.PropModel("Windmill", parent)
	WorldKit.UprightCylinder({
		Name = "Tower",
		Position = base + Vector3.new(0, 9, 0),
		Height = 18,
		Diameter = 9,
		Color = Color3.fromRGB(245, 235, 215),
		Material = Enum.Material.Brick,
		Parent = model,
	})
	WorldKit.UprightCylinder({
		Name = "Roof",
		Position = base + Vector3.new(0, 19.5, 0),
		Height = 3,
		Diameter = 10,
		Color = Color3.fromRGB(190, 70, 60),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	WorldKit.Sphere({
		Name = "RoofCap",
		Position = base + Vector3.new(0, 21, 0),
		Diameter = 7,
		Color = Color3.fromRGB(190, 70, 60),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	decor({
		Name = "Door",
		Size = Vector3.new(3, 5, 0.4),
		Position = base + Vector3.new(0, 2.5, 4.5), -- faces north, toward the map
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.Wood,
		Parent = model,
	})

	-- Sails: their own model, spun by the client (SpinnerController). On
	-- the north face, where players look at it from.
	local hub = base + Vector3.new(0, 16, 5.2)
	local sails = Instance.new("Model")
	sails.Name = "Sails"
	local hubPart = decor({
		Name = "Hub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 1.6, 1.6),
		CFrame = CFrame.new(hub) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(90, 60, 40),
		Parent = sails,
	})
	sails.PrimaryPart = hubPart
	for i = 0, 3 do
		local spin = CFrame.new(hub) * CFrame.Angles(0, 0, i * math.pi / 2)
		decor({
			Name = `Arm{i}`,
			Size = Vector3.new(0.4, 12, 0.3),
			CFrame = spin * CFrame.new(0, 6.5, 0.2),
			Color = Color3.fromRGB(110, 75, 45),
			Material = Enum.Material.Wood,
			Parent = sails,
		})
		decor({
			Name = `Sail{i}`,
			Size = Vector3.new(3.2, 10, 0.15),
			CFrame = spin * CFrame.new(1.8, 7, 0.25),
			Color = Color3.fromRGB(250, 245, 235),
			Material = Enum.Material.Fabric,
			Parent = sails,
		})
	end
	sails:SetAttribute("SpinAxis", "Z")
	sails:SetAttribute("SpinSpeed", 35)
	CollectionService:AddTag(sails, Constants.TAGS.Spinner)
	sails.Parent = model
end

local function buildTulipFields(parent: Instance, rng: Random)
	local rect = WorldLayout.Wilds.TulipFields :: Rect
	local folder = WorldKit.Group("TulipFields", parent)
	local rowSpacing = 5
	local rows = math.floor((rect.Size.Z - 6) / rowSpacing)
	local minX = rect.Center.X - rect.Size.X / 2 + 4
	local maxX = rect.Center.X + rect.Size.X / 2 - 4
	local windmillX = rect.Center.X
	-- Fields are broken into beds with gaps (walkways) between them, each
	-- bed one colour per row - the striped look of a real bulb field.
	local bedWidth, gap = 44, 10
	local bedIndex = 0
	local x0 = minX
	while x0 + bedWidth <= maxX do
		local bedCentreX = x0 + bedWidth / 2
		if math.abs(bedCentreX - windmillX) > 14 then
			bedIndex += 1
			local bed = WorldKit.PropModel(`TulipBed{bedIndex}`, folder)
			for row = 0, rows - 1 do
				local z = rect.Center.Z - rect.Size.Z / 2 + 3 + row * rowSpacing + rowSpacing / 2
				if useTerrain() then
					-- A dirt ridge under each row, grass between rows.
					Workspace.Terrain:FillBlock(
						CFrame.new(bedCentreX, SURFACE_Y - 2, z),
						Vector3.new(bedWidth, 4, 2.2),
						Enum.Material.Ground
					)
				end
				local color = TULIP_COLORS[(row + bedIndex) % #TULIP_COLORS + 1]
				for x = x0 + 1.5, x0 + bedWidth - 1.5, 3 do
					local spot = Vector3.new(x + rng:NextNumber(-0.3, 0.3), WorldLayout.GroundY, z)
					if not PathRegistry.IsNearPath(spot, 1) then
						decor({
							Name = "Tulip",
							Shape = Enum.PartType.Ball,
							Size = Vector3.new(0.9, 1.2, 0.9),
							Position = spot + Vector3.new(0, 1.1, 0),
							Color = color,
							Parent = bed,
						})
					end
				end
			end
		end
		x0 += bedWidth + gap
	end
	windmill(folder, Vector3.new(windmillX, WorldLayout.GroundY, rect.Center.Z))
	areaSign(folder, Vector3.new(windmillX - 10, WorldLayout.GroundY, rect.Center.Z + rect.Size.Z / 2 - 2), "TULIP FIELDS", Color3.fromRGB(255, 200, 90))
end

-- === Rock outcrops ===========================================================

local function buildOutcrops(rng: Random)
	if not useTerrain() then
		return
	end
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(140, 138, 130))
	local plate = WorldLayout.GroundPlate
	local placed = 0
	for _ = 1, 400 do
		if placed >= 22 then
			break
		end
		local spot = Vector3.new(
			plate.Center.X + rng:NextNumber(-plate.Size.X / 2 + 35, plate.Size.X / 2 - 35),
			WorldLayout.GroundY,
			plate.Center.Z + rng:NextNumber(-plate.Size.Z / 2 + 35, plate.Size.Z / 2 - 35)
		)
		local radius = rng:NextNumber(3, 6)
		local zoneClear = WorldLayout.ZoneAt(spot) == nil
		for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
			if
				math.abs(spot.X - zone.Center.X) <= zone.Size.X / 2 + radius + 6
				and math.abs(spot.Z - zone.Center.Z) <= zone.Size.Z / 2 + radius + 6
			then
				zoneClear = false
				break
			end
		end
		if zoneClear and not PathRegistry.IsNearPath(spot, radius + 4) then
			placed += 1
			-- Two overlapping, half-buried balls read as a natural boulder.
			terrain:FillBall(spot + Vector3.new(0, -radius * 0.4, 0), radius, Enum.Material.Rock)
			terrain:FillBall(spot + Vector3.new(radius * 0.6, -radius * 0.6, radius * 0.3), radius * 0.7, Enum.Material.Rock)
			PathRegistry.Add(spot, Vector3.new(radius * 2.4, 1, radius * 2.4))
		end
	end
end

-- === Backdrops ===============================================================

local function cone(centre: Vector3, radius: number, height: number, materialAt: (number) -> Enum.Material, topRadius: number)
	local terrain = Workspace.Terrain
	local step = 4
	for h = 0, height - step, step do
		local t = h / height
		local r = radius + (topRadius - radius) * t
		terrain:FillCylinder(CFrame.new(centre.X, centre.Y + h + step / 2, centre.Z), step, r, materialAt(t))
	end
end

local function buildVolcano(parent: Instance)
	local centre = WorldLayout.Backdrops.Volcano
	local radius, height, craterRadius = 100, 84, 18
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(58, 50, 54))
	cone(centre, radius, height, function()
		return Enum.Material.Basalt
	end, craterRadius + 6)
	-- Crater: hollow out the top, pool of lava at the bottom.
	local top = centre.Y + height
	terrain:FillCylinder(CFrame.new(centre.X, top - 5, centre.Z), 12, craterRadius, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(centre.X, top - 11, centre.Z), 4, craterRadius, Enum.Material.CrackedLava)

	local folder = WorldKit.Group("Volcano", parent)
	local lavaColor = Color3.fromRGB(255, 110, 30)
	local pool = decor({
		Name = "LavaPool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, craterRadius * 2 - 2, craterRadius * 2 - 2),
		CFrame = CFrame.new(centre.X, top - 8.5, centre.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = lavaColor,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	WorldKit.Light({ Name = "LavaGlow", Color = lavaColor, Brightness = 4, Range = 60, Parent = pool })

	-- Lava streams down the slope, facing the map so players see them.
	for _, angle in { math.rad(80), math.rad(100), math.rad(120) } do
		local previous: Vector3? = nil
		for h = height - 6, 8, -12 do
			local t = h / height
			local r = radius + (craterRadius + 6 - radius) * t + 1.2
			local point = Vector3.new(centre.X + math.cos(angle) * r, centre.Y + h, centre.Z + math.sin(angle) * r)
			if previous then
				local length = (point - previous).Magnitude
				decor({
					Name = "LavaFlow",
					Size = Vector3.new(4, 1.2, length + 1),
					CFrame = CFrame.lookAt((previous + point) / 2, point),
					Color = lavaColor,
					Material = Enum.Material.Neon,
					Parent = folder,
				})
			end
			previous = point
		end
	end

	-- Smoke and embers above the crater (decor: off on low graphics).
	local vent = decor({
		Name = "Vent",
		Size = Vector3.new(craterRadius, 2, craterRadius),
		Position = Vector3.new(centre.X, top, centre.Z),
		Transparency = 1,
		Parent = folder,
	})
	WorldKit.Emitter({
		Name = "Smoke",
		Color = Color3.fromRGB(90, 85, 90),
		Rate = 6,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(6, 10),
		SpreadAngle = Vector2.new(15, 15),
		LightEmission = 0,
		SizeSequence = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 8),
			NumberSequenceKeypoint.new(1, 30),
		}),
		TransparencySequence = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = vent,
	})
	WorldKit.Emitter({
		Name = "Embers",
		Color = Color3.fromRGB(255, 150, 40),
		Rate = 12,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(25, 25),
		LightEmission = 1,
		Parent = vent,
	})
end

local function buildMountains()
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(245, 248, 255))
	for _, peak in WorldLayout.Backdrops.Mountains do
		cone(peak.Center, peak.Radius, peak.Height, function(t)
			return if t < 0.55 then Enum.Material.Rock else Enum.Material.Snow
		end, 6)
	end
end

function WildsZone.Build(parent: Instance)
	local folder = WorldKit.Group("Wilds", parent)
	local rng = Random.new(SEED)
	buildCandyLand(folder, rng)
	buildCrystalGrove(folder, rng)
	buildTulipFields(folder, rng)
	if useTerrain() then
		local ok, err = pcall(function()
			buildVolcano(folder)
			buildMountains()
		end)
		if not ok then
			warn(`[WildsZone] backdrops failed: {err}`)
		end
	end
	-- Keep LandscapeZone's trees (and the outcrops) out of the themed areas.
	for _, rect in WorldLayout.Wilds :: { [string]: Rect } do
		PathRegistry.Add(rect.Center, rect.Size)
	end
	buildOutcrops(rng)
end

return WildsZone
