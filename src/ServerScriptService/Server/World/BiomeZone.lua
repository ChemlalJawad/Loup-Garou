--!strict
-- The base biome: what turns a flat plate floating in the void into a
-- meadow valley.
--
--   * Rolling hills along the map edge, plus an invisible wall at the edge,
--     so nobody (especially a young player) can walk off the world.
--   * A grass skirt and a ring of big distant hills out past the edge, so the
--     horizon is countryside instead of void.
--   * A lily pond with a wooden dock in the north-west wilds (a dirt trail
--     from the Arena street leads there - see MapBuilder).
--   * Two giant golden/diamond Brainrot statues as skyline landmarks.
--   * Meadow patches (lighter/darker grass) that break up the flat lawn.
--   * Fireflies at night and drifting pollen by day (tagged DecorEmitter +
--     DecorTime, so LightingController follows the day/night cycle and turns
--     them off on low graphics quality).
--
-- Not a WorldLayout zone - it owns no rectangle. Order 150 runs after every
-- real zone but before LandscapeZone (200): the pond and the hill band are
-- registered in PathRegistry as keep-out rects so no tree lands in the water
-- or inside a hill.
--
-- Cost: ~80 edge hills + 24 horizon hills + 4 skirt parts + 4 walls + ~40
-- pond parts + ~45 meadow patches + 16 emitter anchors = ~215 parts, almost
-- all of them non-colliding, non-queryable and shadowless.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local BrainrotModels = require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
local Mutations = require(ReplicatedStorage.Shared.Brainrots.Mutations)
local WorldKit = require(script.Parent.WorldKit)
local PathRegistry = require(script.Parent.PathRegistry)

local BiomeZone = {}
BiomeZone.Order = 150

local SEED = 20260930
local GRASS = Color3.fromRGB(96, 170, 88)

local HILL_SPACING = 34
local HILL_OUTWARD_OFFSET = 8 -- hill centres sit just outside the edge
local HILL_BAND = 30 -- how far hills reach inward; kept free of props
local WALL_HEIGHT = 220 -- tall enough that jump pads can't clear it

local POND_CENTER = WorldLayout.Landmarks.LilyPond
local POND_DIAMETER = 46

local MEADOW_PATCHES = 45
local FIREFLY_SPOTS = 14

-- True when TerrainZone (Order 140) built the terrain ground successfully.
local function useTerrain(): boolean
	return Workspace.Terrain:GetAttribute("HatchWarsTerrain") == true
end

local function insideAnyZone(position: Vector3, margin: number): boolean
	for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		if
			math.abs(position.X - zone.Center.X) <= zone.Size.X / 2 + margin
			and math.abs(position.Z - zone.Center.Z) <= zone.Size.Z / 2 + margin
		then
			return true
		end
	end
	return false
end

local function isOpenGround(position: Vector3, margin: number): boolean
	return not insideAnyZone(position, margin) and not PathRegistry.IsNearPath(position, margin)
end

-- A decorative, non-interactive part: the cheapest kind there is.
local function decor(props: WorldKit.PartProps): Part
	props.CanCollide = false
	props.CanTouch = false
	props.CastShadow = false
	return WorldKit.Part(props)
end

local function decorCylinder(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance, name: string): Part
	return decor({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- === Edge: hills, walls, skirt, horizon =====================================

local function buildEdge(parent: Instance, rng: Random)
	local folder = WorldKit.Group("Edge", parent)
	local plate = WorldLayout.GroundPlate
	local groundY = WorldLayout.GroundY
	local minX = plate.Center.X - plate.Size.X / 2
	local maxX = plate.Center.X + plate.Size.X / 2
	local minZ = plate.Center.Z - plate.Size.Z / 2
	local maxZ = plate.Center.Z + plate.Size.Z / 2

	-- Each side: start point, direction along the edge, outward normal, length.
	local sides = {
		{ Start = Vector3.new(minX, 0, minZ), Along = Vector3.new(1, 0, 0), Out = Vector3.new(0, 0, -1), Length = maxX - minX },
		{ Start = Vector3.new(minX, 0, maxZ), Along = Vector3.new(1, 0, 0), Out = Vector3.new(0, 0, 1), Length = maxX - minX },
		{ Start = Vector3.new(minX, 0, minZ), Along = Vector3.new(0, 0, 1), Out = Vector3.new(-1, 0, 0), Length = maxZ - minZ },
		{ Start = Vector3.new(maxX, 0, minZ), Along = Vector3.new(0, 0, 1), Out = Vector3.new(1, 0, 0), Length = maxZ - minZ },
	}

	local hills = WorldKit.Group("EdgeHills", folder)
	for sideIndex, side in sides do
		local count = math.floor(side.Length / HILL_SPACING)
		for i = 0, count do
			local along = side.Start + side.Along * (i * side.Length / count)
			local diameter = rng:NextNumber(46, 66)
			local radius = diameter / 2
			local centre = along + side.Out * (HILL_OUTWARD_OFFSET + rng:NextNumber(0, 6))
			-- Where the hill meets the ground it reaches ~0.94r inward; skip
			-- any hill that would poke into a zone (the Arena runs right up
			-- to the north edge and has its own walls).
			local innerPoint = centre - side.Out * (radius * 0.94)
			if not insideAnyZone(innerPoint, 4) and not PathRegistry.IsNearPath(innerPoint, 2) then
				local shade = rng:NextNumber(-0.06, 0.06)
				if useTerrain() then
					-- Smooth terrain hill: blends into the grass with no seam,
					-- and grows the same swaying blades.
					Workspace.Terrain:FillBall(centre + Vector3.new(0, groundY - radius * 0.35, 0), radius, Enum.Material.Grass)
					continue
				end
				WorldKit.Part({
					Name = `Hill{sideIndex}_{i}`,
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(diameter, diameter, diameter),
					Position = centre + Vector3.new(0, groundY - radius * 0.35, 0),
					Color = GRASS:Lerp(if shade > 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(shade)),
					Material = Enum.Material.Grass,
					-- Solid, so hills are something to scramble up, but no
					-- shadow: 80 huge balls would dominate the shadow budget.
					CastShadow = false,
					CanTouch = false,
					Parent = hills,
				})
			end
		end

		-- Keep props out of the band the hills cover.
		local bandCentre = side.Start + side.Along * (side.Length / 2) - side.Out * (HILL_BAND / 2)
		local bandSize = if side.Along.X ~= 0
			then Vector3.new(side.Length, 1, HILL_BAND)
			else Vector3.new(HILL_BAND, 1, side.Length)
		PathRegistry.Add(bandCentre, bandSize)

		-- Invisible wall exactly at the edge: the hills make the edge feel
		-- natural, the wall makes it safe.
		local wallThickness = 4
		local wallCentre = side.Start
			+ side.Along * (side.Length / 2)
			+ side.Out * (wallThickness / 2)
			+ Vector3.new(0, groundY + WALL_HEIGHT / 2, 0)
		WorldKit.Part({
			Name = `BoundaryWall{sideIndex}`,
			Size = if side.Along.X ~= 0
				then Vector3.new(side.Length + wallThickness * 2, WALL_HEIGHT, wallThickness)
				else Vector3.new(wallThickness, WALL_HEIGHT, side.Length + wallThickness * 2),
			Position = wallCentre,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	-- Grass skirt out to the horizon: four big flat parts around the plate,
	-- slightly darker so the playable area still reads as "the place".
	local skirtColor = GRASS:Lerp(Color3.fromRGB(40, 80, 50), 0.25)
	local reach = 600
	local skirtY = groundY - 0.6
	local skirts = {
		{ Centre = Vector3.new(plate.Center.X, skirtY, maxZ + reach / 2), Size = Vector3.new(plate.Size.X + reach * 2, 1, reach) },
		{ Centre = Vector3.new(plate.Center.X, skirtY, minZ - reach / 2), Size = Vector3.new(plate.Size.X + reach * 2, 1, reach) },
		{ Centre = Vector3.new(maxX + reach / 2, skirtY, plate.Center.Z), Size = Vector3.new(reach, 1, plate.Size.Z) },
		{ Centre = Vector3.new(minX - reach / 2, skirtY, plate.Center.Z), Size = Vector3.new(reach, 1, plate.Size.Z) },
	}
	for i, skirt in skirts do
		decor({
			Name = `Skirt{i}`,
			Size = skirt.Size,
			Position = skirt.Centre,
			Color = skirtColor,
			Material = Enum.Material.Grass,
			Parent = folder,
		})
	end

	-- A ring of big, soft hills on the horizon for a valley silhouette.
	local horizon = WorldKit.Group("HorizonHills", folder)
	local centre = plate.Center
	local halfDiagonal = math.sqrt((plate.Size.X / 2) ^ 2 + (plate.Size.Z / 2) ^ 2)
	for i = 1, 24 do
		local angle = (i / 24) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local distance = halfDiagonal + rng:NextNumber(90, 220)
		local diameter = rng:NextNumber(150, 260)
		local tint = rng:NextNumber(0.15, 0.4) -- further = hazier
		decor({
			Name = `HorizonHill{i}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(diameter, diameter, diameter),
			Position = Vector3.new(
				centre.X + math.cos(angle) * distance,
				groundY - diameter * 0.3,
				centre.Z + math.sin(angle) * distance
			),
			Color = skirtColor:Lerp(Color3.fromRGB(150, 190, 210), tint),
			Material = Enum.Material.Grass,
			Parent = horizon,
		})
	end
end

-- === Pond ===================================================================

local function buildPond(parent: Instance, rng: Random)
	local groundY = WorldLayout.GroundY
	local centre = Vector3.new(POND_CENTER.X, groundY, POND_CENTER.Z)
	-- Zones only: MapBuilder's trail deliberately runs right up to the beach.
	if insideAnyZone(centre, POND_DIAMETER / 2 + 8) then
		warn("[BiomeZone] pond site overlaps a zone - skipped")
		return
	end
	local pond = WorldKit.Group("LilyPond", parent)
	PathRegistry.Add(centre, Vector3.new(POND_DIAMETER + 20, 1, POND_DIAMETER + 20))

	-- With terrain, TerrainZone already dug a real pond (beach, basin,
	-- water); only the part fallback needs the flat layered discs.
	local terrainPond = useTerrain()
	-- Layers stacked a few hundredths apart so no two faces are coplanar.
	if not terrainPond then
		decorCylinder(centre + Vector3.new(0, 0.02, 0), POND_DIAMETER + 8, 0.1, Color3.fromRGB(232, 214, 160), Enum.Material.Sand, pond, "Beach")
		decorCylinder(centre + Vector3.new(0, 0.05, 0), POND_DIAMETER, 0.1, Color3.fromRGB(34, 86, 120), Enum.Material.SmoothPlastic, pond, "PondBed")
		-- Non-colliding water: you wade through it ankle-deep instead of
		-- walking on top of it.
		decorCylinder(centre + Vector3.new(0, 0.3, 0), POND_DIAMETER, 0.5, Color3.fromRGB(90, 180, 235), Enum.Material.Glass, pond, "Water").Transparency = 0.35
	end
	-- Pads float on the surface: terrain water sits just under grass level.
	local padY = if terrainPond then -0.5 else 0.6

	local radius = POND_DIAMETER / 2
	-- Lily pads (solid, to hop across) with the odd pink flower.
	for i = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(4, radius - 5)
		local spot = centre + Vector3.new(math.cos(angle) * distance, padY, math.sin(angle) * distance)
		WorldKit.UprightCylinder({
			Name = `LilyPad{i}`,
			Position = spot,
			Height = 0.2,
			Diameter = rng:NextNumber(2.6, 3.6),
			Color = Color3.fromRGB(70, 160, 80),
			CastShadow = false,
			Parent = pond,
		})
		if i % 3 == 0 then
			WorldKit.Sphere({
				Name = `LilyFlower{i}`,
				Position = spot + Vector3.new(0.4, 0.4, 0.2),
				Diameter = 0.8,
				Color = Color3.fromRGB(255, 150, 200),
				CanCollide = false,
				CastShadow = false,
				Parent = pond,
			})
		end
	end

	-- Rocks and reeds around the rim, leaving the dock side (east) open.
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		if math.abs(math.cos(angle) - 1) > 0.12 then
			local rim = centre + Vector3.new(math.cos(angle) * (radius + 2), 0, math.sin(angle) * (radius + 2))
			if i % 2 == 0 then
				WorldKit.Rock({ Position = rim, Size = rng:NextNumber(2, 3.5), Yaw = angle, Parent = pond })
			else
				for r = 1, 3 do
					local height = rng:NextNumber(2.5, 4)
					WorldKit.UprightCylinder({
						Name = "Reed",
						Position = rim + Vector3.new(r * 0.5 - 1, height / 2, r * 0.3),
						Height = height,
						Diameter = 0.25,
						Color = Color3.fromRGB(110, 150, 70),
						CanCollide = false,
						CastShadow = false,
						Parent = pond,
					})
				end
			end
		end
	end

	-- Wooden dock from the east shore out over the water.
	local dockLength = 14
	local dockCentre = centre + Vector3.new(radius - dockLength / 2 + 3, 1, 0)
	WorldKit.Part({
		Name = "Dock",
		Size = Vector3.new(dockLength, 0.5, 5),
		Position = dockCentre,
		Color = Color3.fromRGB(150, 104, 66),
		Material = Enum.Material.WoodPlanks,
		Parent = pond,
	})
	for i, offset in { Vector3.new(-dockLength / 2 + 0.6, 0, 2.2), Vector3.new(-dockLength / 2 + 0.6, 0, -2.2) } do
		WorldKit.UprightCylinder({
			Name = `DockPost{i}`,
			Position = dockCentre + offset + Vector3.new(0, 0.2, 0),
			Height = 2.4,
			Diameter = 0.6,
			Color = Color3.fromRGB(120, 82, 52),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = pond,
		})
	end
	local signPost = WorldKit.UprightCylinder({
		Name = "SignPost",
		Position = dockCentre + Vector3.new(dockLength / 2 + 1, 1.5, 3),
		Height = 3,
		Diameter = 0.5,
		Color = Color3.fromRGB(120, 82, 52),
		Material = Enum.Material.Wood,
		CastShadow = false,
		Parent = pond,
	})
	WorldKit.Sign({
		Name = "PondSign",
		Text = "LILY POND",
		Adornee = signPost,
		StudsOffset = Vector3.new(0, 3, 0),
		MaxDistance = 90,
	})

	-- Picnic blanket on the west shore: a hangout spot to sit with friends.
	local picnic = centre + Vector3.new(-(radius + 7), 0, 4)
	for row = 0, 1 do
		for col = 0, 1 do
			decor({
				Name = "PicnicBlanket",
				Size = Vector3.new(3, 0.1, 3),
				Position = picnic + Vector3.new(col * 3 - 1.5, 0.03, row * 3 - 1.5),
				Color = if (row + col) % 2 == 0 then Color3.fromRGB(230, 70, 80) else Color3.fromRGB(250, 245, 235),
				Material = Enum.Material.Fabric,
				Parent = pond,
			})
		end
	end
	WorldKit.Part({
		Name = "PicnicBasket",
		Size = Vector3.new(1.6, 1.1, 1.1),
		Position = picnic + Vector3.new(1.2, 0.6, 1.2),
		Color = Color3.fromRGB(176, 124, 70),
		Material = Enum.Material.Wood,
		CastShadow = false,
		Parent = pond,
	})

	-- Fireflies over the water at night, pollen by day.
	local anchor = decor({
		Name = "PondMotes",
		Size = Vector3.new(POND_DIAMETER, 4, POND_DIAMETER),
		Position = centre + Vector3.new(0, 3, 0),
		Transparency = 1,
		Parent = pond,
	})
	local fireflies = WorldKit.Emitter({
		Name = "Fireflies",
		Color = Color3.fromRGB(220, 255, 120),
		Rate = 6,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(0.3, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		SizeSequence = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = anchor,
	})
	fireflies:SetAttribute("DecorTime", "Night")
end

-- === Giant Brainrot statues =================================================

-- The two rarest characters, cast in gold and diamond, five times life size,
-- facing the Central Plaza. Skyline landmarks ("meet at the gold shark!")
-- and a preview of what the rarest eggs hold.
local STATUES = {
	{ Spot = WorldLayout.Landmarks.StatueWest, Species = "TralaleroAstrale", Rarity = "Secret", Mutation = "Gold" },
	{ Spot = WorldLayout.Landmarks.StatueEast, Species = "CrocobrividoVulcanico", Rarity = "Legendary", Mutation = "Diamond" },
}
local STATUE_SCALE = 5
local PEDESTAL_DIAMETER = 14
local PEDESTAL_HEIGHT = 3

local function buildStatue(parent: Instance, statue: { Spot: Vector3, Species: string, Rarity: string, Mutation: string })
	local spot = Vector3.new(statue.Spot.X, WorldLayout.GroundY, statue.Spot.Z)
	if not isOpenGround(spot, PEDESTAL_DIAMETER / 2 + 2) then
		warn(`[BiomeZone] statue site for {statue.Species} overlaps a zone or path - skipped`)
		return
	end
	PathRegistry.Add(spot, Vector3.new(PEDESTAL_DIAMETER + 8, 1, PEDESTAL_DIAMETER + 8))

	local group = WorldKit.Group(`Statue_{statue.Species}`, parent)
	WorldKit.UprightCylinder({
		Name = "Pedestal",
		Position = spot + Vector3.new(0, PEDESTAL_HEIGHT / 2, 0),
		Height = PEDESTAL_HEIGHT,
		Diameter = PEDESTAL_DIAMETER,
		Color = Color3.fromRGB(236, 230, 214),
		Material = Enum.Material.Marble,
		Parent = group,
	})
	WorldKit.UprightCylinder({
		Name = "PedestalTrim",
		Position = spot + Vector3.new(0, PEDESTAL_HEIGHT + 0.1, 0),
		Height = 0.2,
		Diameter = PEDESTAL_DIAMETER + 0.6,
		Color = Color3.fromRGB(255, 205, 80),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = group,
	})

	local ok, result = pcall(BrainrotModels.BuildStatic, statue.Species, statue.Rarity :: any)
	if not ok or typeof(result) ~= "Instance" then
		warn(`[BiomeZone] could not build statue {statue.Species}: {result}`)
		return
	end
	local model = result :: Model
	model.Name = "Statue"
	model:ScaleTo(STATUE_SCALE)
	-- Models are built around the origin; face the Plaza, then sit the
	-- model's lowest point on the pedestal.
	local buildPivot = model:GetPivot()
	local hub = WorldLayout.Get("Hub").Center
	local lookAt = Vector3.new(hub.X, spot.Y, hub.Z)
	model:PivotTo(CFrame.lookAt(spot, lookAt) * buildPivot)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, spot.Y + PEDESTAL_HEIGHT + 0.2 - bottom, 0))
	Mutations.ApplyVisual(model, statue.Mutation)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			-- Giant statue: solid, so kids can climb onto its feet.
			-- (BrainrotModels already limits shadows to the root part.)
			descendant.CanCollide = true
		end
	end
	model.Parent = group

	local plaque = WorldKit.Part({
		Name = "Plaque",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = spot + Vector3.new(0, PEDESTAL_HEIGHT, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = group,
	})
	WorldKit.Sign({
		Name = "StatueSign",
		Adornee = plaque,
		Text = Mutations.DecorateName(EggConfig.DisplayName(statue.Species), statue.Mutation),
		Color = Color3.fromRGB(255, 225, 120),
		Size = UDim2.new(0, 300, 0, 44),
		TextSize = 22,
		StudsOffset = Vector3.new(0, boxSize.Y + 4, 0),
		MaxDistance = 160,
	})
end

-- === Meadow patches + fireflies ==============================================

local function buildMeadow(parent: Instance, rng: Random)
	local folder = WorldKit.Group("Meadow", parent)
	local plate = WorldLayout.GroundPlate
	local groundY = WorldLayout.GroundY
	local halfX = plate.Size.X / 2 - HILL_BAND
	local halfZ = plate.Size.Z / 2 - HILL_BAND
	local shades = {
		GRASS:Lerp(Color3.new(1, 1, 1), 0.12),
		GRASS:Lerp(Color3.new(0, 0, 0), 0.12),
		GRASS:Lerp(Color3.fromRGB(230, 220, 110), 0.25), -- sunny, buttercup-y
	}

	local function randomOpenSpot(margin: number): Vector3?
		for _ = 1, 40 do
			local spot = Vector3.new(
				plate.Center.X + rng:NextNumber(-halfX, halfX),
				groundY,
				plate.Center.Z + rng:NextNumber(-halfZ, halfZ)
			)
			if isOpenGround(spot, margin) then
				return spot
			end
		end
		return nil
	end

	-- Terrain grass blades already give the lawn texture, and thin patch
	-- parts would have blades poking through them.
	for i = 1, if useTerrain() then 0 else MEADOW_PATCHES do
		local diameter = rng:NextNumber(14, 30)
		local spot = randomOpenSpot(diameter / 2 + 1)
		if spot then
			-- Paper-thin, just above the ground plate (which sits 0.05 below
			-- GroundY), below path and zone floors: no z-fighting either way.
			decorCylinder(spot + Vector3.new(0, -0.02, 0), diameter, 0.04, shades[(i - 1) % #shades + 1], Enum.Material.Grass, folder, `Patch{i}`)
		end
	end

	for i = 1, FIREFLY_SPOTS do
		local spot = randomOpenSpot(6)
		if spot then
			local anchor = decor({
				Name = `Motes{i}`,
				Size = Vector3.new(26, 5, 26),
				Position = spot + Vector3.new(0, 3, 0),
				Transparency = 1,
				Parent = folder,
			})
			local fireflies = WorldKit.Emitter({
				Name = "Fireflies",
				Color = Color3.fromRGB(220, 255, 120),
				Rate = 3,
				Lifetime = NumberRange.new(3, 5),
				Speed = NumberRange.new(0.3, 1.2),
				SpreadAngle = Vector2.new(180, 180),
				LightEmission = 1,
				SizeSequence = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(0.5, 0.3),
					NumberSequenceKeypoint.new(1, 0),
				}),
				Parent = anchor,
			})
			fireflies:SetAttribute("DecorTime", "Night")
			local pollen = WorldKit.Emitter({
				Name = "Pollen",
				Color = Color3.fromRGB(255, 250, 200),
				Rate = 2,
				Lifetime = NumberRange.new(4, 6),
				Speed = NumberRange.new(0.2, 0.8),
				SpreadAngle = Vector2.new(180, 180),
				LightEmission = 0.3,
				SizeSequence = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.15),
					NumberSequenceKeypoint.new(1, 0),
				}),
				Parent = anchor,
			})
			pollen:SetAttribute("DecorTime", "Day")
		end
	end
end

function BiomeZone.Build(parent: Instance)
	local folder = WorldKit.Group("Biome", parent)
	local rng = Random.new(SEED)
	buildEdge(folder, rng)
	buildPond(folder, rng)
	for _, statue in STATUES do
		buildStatue(folder, statue)
	end
	buildMeadow(folder, rng)
end

return BiomeZone
