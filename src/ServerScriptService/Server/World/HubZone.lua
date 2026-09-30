--!strict
-- Central Plaza — the hub every player spawns into and returns to between
-- activities. Owns the game's ONE Neutral SpawnLocation; without it players
-- fall back to a raw world-origin spawn with nothing built around them, so
-- this file is load-bearing, not decorative.
--
-- Coordinate convention: everything below is authored in Hub-local offsets
-- from `WorldLayout.Get("Hub").Center` (world position = center + offset).
-- The rect is 150 (X) x 150 (Z), so local X spans [-75, 75] and local Z spans
-- [-75, 75]. Four gateways face the four zones MapBuilder's paths connect to:
--   -Z (south)  -> Hatchery   (PathHubHatchery, AccentSecondary/purple)
--   +X (east)   -> Commercial (PathHubCommercial, Robux/green)
--   -X (west)   -> Plaza      (PathHubPlaza, AccentWarning/gold)
--   +Z (north)  -> Arena      (PathHubArena, AccentPrimary/neon-green - the
--                  widest path, since CTF is the game's main event)
--
-- Elevation is stepped outward from a raised centre platform down to ground
-- level at the gateways, each tier's bottom flush with the previous tier's
-- top (no floating gaps, no coplanar z-fighting):
--   Tier 0 (outer ring, gateways)  top = WorldLayout.GroundY
--   Tier 1 (mid ring)              top = WorldLayout.GroundY + 1
--   Tier 2 (inner dais)            top = WorldLayout.GroundY + 2
--   Landmark base sits on Tier 2.
--
-- Rough part budget (~150x150 zone, TiledFloor is the main cost - kept to
-- TileSize=15 for the big rings, TileSize=5 only on the small inner dais):
--   Outer ring floor (TiledFloor, 150x150 minus inner cutout via a single
--     slab + inner rings drawn over it): ~1 slab + 2 ring TiledFloors
--     (~10x10=100 tiles each at TileSize=15) -> ~1 + 100 = ~101
--   Actually rings implemented as plain colored slabs (not full tiled) to
--   keep the count sane: 3 tiers x 1 slab + edge trim(4) = 3 + 12 = 15
--   Landmark: ~18 parts (stacked cylinders/spheres + emitter + lights)
--   4x Gateway arch: 2 pillars + 1 lintel + neon trim(2) + sign = 6 each = 24
--   Colonnade ring: 12 pillars (Pillar = 2 parts w/ cap) = 24
--   Benches/planters (6 pockets x 3 parts) = 18
--   Viewing deck + railing (1 deck + Railing ~6 posts+rail) = 8
--   Spawn pad + spawn = 2
--   Total ~ 110 parts, comfortably under the ~400 guideline.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)
local HubWelcome = require(script.Parent.HubWelcome)

local HubZone = {}
HubZone.Order = 10 -- built first among decorative zones: it's the spawn.

-- Pastel lilac stone for arches, fountain and pillars: contrasts with the
-- cream paving and stays playful. (Was near-black, which made the spawn -
-- every player's first impression - read as a night-time car park.)
local STONE = Color3.fromRGB(150, 140, 190)
local STONE_LIGHT = Color3.fromRGB(178, 168, 214)

local GATEWAY_COLORS = {
	South = Theme.Color.AccentSecondary,
	East = Theme.Color.Robux,
	West = Theme.Color.AccentWarning,
	North = Theme.Color.AccentPrimary,
}

local function buildGateway(folder: Instance, name: string, position: Vector3, facing: Vector3, color: Color3, label: string)
	-- `facing` is a unit-ish vector pointing OUT of the hub through the
	-- gateway; the arch's lintel spans perpendicular to it.
	local spanAxis = if math.abs(facing.X) > math.abs(facing.Z) then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local archWidth = 16
	local archHeight = 14
	local postOffset = spanAxis * (archWidth / 2)

	for _, sign in { 1, -1 } do
		WorldKit.Pillar({
			Name = `{name}Post{sign}`,
			Position = position + postOffset * sign,
			Height = archHeight,
			Thickness = 2.2,
			Color = STONE,
			CapColor = color,
			Parent = folder,
		})
	end

	WorldKit.Part({
		Name = `{name}Lintel`,
		Size = if spanAxis.Z > 0 then Vector3.new(2.4, 2, archWidth + 2) else Vector3.new(archWidth + 2, 2, 2.4),
		Position = position + Vector3.new(0, archHeight + 1, 0),
		Color = STONE,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	WorldKit.Part({
		Name = `{name}LintelTrim`,
		Size = if spanAxis.Z > 0 then Vector3.new(0.4, 0.4, archWidth + 2) else Vector3.new(archWidth + 2, 0.4, 0.4),
		Position = position + Vector3.new(0, archHeight, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})

	local signPost = WorldKit.Part({
		Name = `{name}SignPost`,
		Size = Vector3.new(1, 6, 1),
		Position = position + Vector3.new(0, archHeight + 5, 0),
		Color = STONE,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = `{name}Sign`,
		Adornee = signPost,
		Text = label,
		Color = color,
		Size = UDim2.new(0, 220, 0, 56),
		StudsOffset = Vector3.new(0, 5, 0),
	})
end

local function buildLandmark(folder: Instance, base: Vector3)
	-- A tiered obelisk-fountain: three shrinking drum sections topped by a
	-- slow-spinning neon shard, ringed by a basin. Tall enough (roughly 34
	-- studs) to read from every gateway.
	local drum1Height, drum1Diameter = 6, 14
	local drum2Height, drum2Diameter = 8, 10
	local drum3Height, drum3Diameter = 10, 6

	WorldKit.UprightCylinder({
		Name = "LandmarkBasin",
		Position = base + Vector3.new(0, 0.5, 0),
		Height = 1,
		Diameter = 22,
		Color = STONE_LIGHT,
		Material = Enum.Material.Marble,
		Parent = folder,
	})
	WorldKit.Emitter({
		Name = "LandmarkMist",
		Parent = WorldKit.Part({
			Name = "LandmarkMistAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = base + Vector3.new(0, 1.5, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		}),
		Color = Theme.Color.AccentPrimary,
		Rate = 6,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(35, 35),
	})

	local y = 1
	local d1Center = y + drum1Height / 2
	WorldKit.UprightCylinder({
		Name = "LandmarkDrum1",
		Position = base + Vector3.new(0, d1Center, 0),
		Height = drum1Height,
		Diameter = drum1Diameter,
		Color = STONE,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	y += drum1Height
	local d2Center = y + drum2Height / 2
	WorldKit.UprightCylinder({
		Name = "LandmarkDrum2",
		Position = base + Vector3.new(0, d2Center, 0),
		Height = drum2Height,
		Diameter = drum2Diameter,
		Color = STONE_LIGHT,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	y += drum2Height
	local d3Center = y + drum3Height / 2
	WorldKit.UprightCylinder({
		Name = "LandmarkDrum3",
		Position = base + Vector3.new(0, d3Center, 0),
		Height = drum3Height,
		Diameter = drum3Diameter,
		Color = STONE,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	y += drum3Height

	-- Neon ring bands at each drum seam - the "designed, not placeholder" tell.
	for _, seamY in { y - drum3Height, y - drum3Height - drum2Height } do
		WorldKit.NeonBorder({
			Name = "LandmarkSeamRing",
			Width = drum2Diameter + 1,
			Depth = drum2Diameter + 1,
			Center = base + Vector3.new(0, seamY, 0),
			Thickness = 0.5,
			Height = 0.3,
			Color = Theme.Color.AccentSecondary,
			Parent = folder,
		})
	end

	-- The shard: a tilted neon crystal the client spins (Spinner tag), so
	-- the plaza's centrepiece is always moving - an eye-catcher from spawn.
	local shardModel = Instance.new("Model")
	shardModel.Name = "LandmarkShard"
	local shard = WorldKit.Part({
		Name = "Shard",
		Size = Vector3.new(2.6, 5, 2.6),
		CFrame = CFrame.new(base + Vector3.new(0, y + 3, 0)) * CFrame.Angles(math.rad(35), 0, math.rad(35)),
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = shardModel,
	})
	shardModel.PrimaryPart = shard
	shardModel:SetAttribute("SpinAxis", "Y")
	shardModel:SetAttribute("SpinSpeed", 40)
	CollectionService:AddTag(shardModel, Constants.TAGS.Spinner)
	shardModel.Parent = folder
	WorldKit.Light({
		Name = "LandmarkLight",
		Parent = WorldKit.Part({
			Name = "LandmarkLightAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = base + Vector3.new(0, y + 2, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		}),
		Color = Theme.Color.AccentPrimary,
		Brightness = 4,
		Range = 40,
	})
end

local function buildSeatingPocket(folder: Instance, position: Vector3, index: number)
	WorldKit.Part({
		Name = `SeatPlanter{index}`,
		Size = Vector3.new(4, 1.6, 4),
		Position = position,
		Color = STONE_LIGHT,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	WorldKit.Part({
		Name = `SeatBenchA{index}`,
		Size = Vector3.new(5, 1.4, 1.4),
		Position = position + Vector3.new(0, 0, 3.2),
		Color = STONE,
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
	WorldKit.Part({
		Name = `SeatBenchB{index}`,
		Size = Vector3.new(5, 1.4, 1.4),
		Position = position + Vector3.new(0, 0, -3.2),
		Color = STONE,
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
end

function HubZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Hub")
	local center = zone.Center
	local groundY = WorldLayout.GroundY

	local folder = WorldKit.Group("Hub", parent)

	-- Tier 0: outer ring at ground level, extends to the rect edges so it
	-- meets MapBuilder's paths flush.
	WorldKit.Part({
		Name = "PlazaOuterRing",
		Size = Vector3.new(zone.Size.X, 1, zone.Size.Z),
		Position = center + Vector3.new(0, groundY - 0.5, 0),
		-- Same paving as the paths, so every walk flows into the plaza.
		Color = WorldKit.Palette.Paving,
		Material = Enum.Material.Cobblestone,
		Parent = folder,
	})

	-- Tier 1: mid ring, one step up.
	local tier1Size = 100
	WorldKit.Part({
		Name = "PlazaMidRing",
		Size = Vector3.new(tier1Size, 1, tier1Size),
		Position = center + Vector3.new(0, groundY + 0.5, 0),
		Color = WorldKit.Palette.PavingLight,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "PlazaMidRingTrim",
		Width = tier1Size,
		Depth = tier1Size,
		Center = center + Vector3.new(0, groundY + 1.05, 0),
		Color = Theme.Color.AccentPrimary,
		Parent = folder,
	})

	-- Tier 2: inner dais, banded tiling for texture, one more step up.
	local tier2Size = 46
	WorldKit.TiledFloor({
		Name = "PlazaDais",
		Width = tier2Size,
		Depth = tier2Size,
		TileSize = 5.75,
		Thickness = 1,
		Position = center + Vector3.new(0, groundY + 1.5, 0),
		ColorA = WorldKit.Palette.TileCream,
		ColorB = WorldKit.Palette.TileRose,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "PlazaDaisTrim",
		Width = tier2Size,
		Depth = tier2Size,
		Center = center + Vector3.new(0, groundY + 2.05, 0),
		Color = Theme.Color.AccentSecondary,
		Parent = folder,
	})

	-- The one Neutral spawn every player lands at: a round marble pad on the
	-- dais, just south of the fountain basin (clear of it - they used to
	-- overlap and z-fight), facing -Z so the first frame looks across the
	-- fountain toward the Hatchery, the new-player guide's first stop.
	-- Rotating about Z to stand the cylinder up keeps LookVector at -Z.
	local spawnCentre = center + Vector3.new(0, groundY + 2.5, 17.5)
	local spawnDiameter = 11
	WorldKit.Spawn({
		Name = "HubSpawn",
		CFrame = CFrame.new(spawnCentre) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, spawnDiameter, spawnDiameter),
		Color = WorldKit.Palette.TileCream,
		Material = Enum.Material.Marble,
		Neutral = true,
		Parent = folder,
	})
	-- Glowing rim: a slightly wider neon disc just under the pad's top.
	WorldKit.UprightCylinder({
		Name = "HubSpawnRim",
		Position = spawnCentre + Vector3.new(0, -0.1, 0),
		Height = 0.9,
		Diameter = spawnDiameter + 1,
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	-- A floating welcome over the pad, readable from the whole plaza.
	local welcomeAnchor = WorldKit.Part({
		Name = "WelcomeAnchor",
		Size = Vector3.new(1, 1, 1),
		Position = spawnCentre + Vector3.new(0, 1, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = "WelcomeSign",
		Adornee = welcomeAnchor,
		Text = "WELCOME TO BRAINROT HATCH WARS!",
		Color = Color3.fromRGB(255, 225, 120),
		Size = UDim2.new(0, 420, 0, 50),
		TextSize = 26,
		StudsOffset = Vector3.new(0, 11, 0),
		MaxDistance = 90,
	})
	-- Rainbow arch, bunting, map board, flowers (see HubWelcome).
	HubWelcome.Build(folder, Vector3.new(spawnCentre.X, groundY + 2, spawnCentre.Z))

	-- Sparkles rising off the pad (decor: off on low graphics quality).
	WorldKit.Emitter({
		Name = "SpawnSparkles",
		Parent = welcomeAnchor,
		Color = Color3.fromRGB(255, 240, 170),
		Rate = 4,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(60, 60),
	})

	buildLandmark(folder, center + Vector3.new(0, groundY + 2, 0))

	-- Colonnade ring around the dais.
	local colonnadeRadius = 30
	local pillarCount = 12
	for i = 1, pillarCount do
		local angle = (i - 1) / pillarCount * math.pi * 2
		WorldKit.Pillar({
			Name = `PlazaColonnade{i}`,
			Position = center + Vector3.new(math.cos(angle) * colonnadeRadius, groundY + 1, math.sin(angle) * colonnadeRadius),
			Height = 10,
			Thickness = 1.6,
			Color = STONE,
			CapColor = Theme.Color.AccentPrimary,
			Parent = folder,
		})
	end

	-- Seating pockets tucked between the mid ring and dais, off the main
	-- north-south/east-west axes so they don't sit in a gateway sightline.
	local seatRadius = 38
	local seatAngles = { math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4 }
	for i, angle in seatAngles do
		buildSeatingPocket(
			folder,
			center + Vector3.new(math.cos(angle) * seatRadius, groundY + 1.5, math.sin(angle) * seatRadius),
			i
		)
	end

	-- Raised viewing deck on the south side (between the Hatchery gateway and
	-- the colonnade), overlooking the plaza.
	local deckCenter = center + Vector3.new(-40, groundY + 3.5, 40)
	WorldKit.Part({
		Name = "ViewingDeck",
		Size = Vector3.new(16, 1, 10),
		Position = deckCenter,
		Color = WorldKit.Palette.Wood,
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
	WorldKit.Stairs({
		Name = "ViewingDeckStairs",
		Steps = 6,
		Width = 6,
		Height = 4,
		Run = 8,
		Axis = "Z",
		Position = deckCenter + Vector3.new(0, -4, 8),
		Color = WorldKit.Palette.Wood,
		Parent = folder,
	})
	WorldKit.Railing({
		Name = "ViewingDeckRail",
		Axis = "X",
		Position = deckCenter + Vector3.new(0, 0.5, -5),
		Length = 16,
		Color = Theme.Color.Stroke,
		Parent = folder,
	})

	-- Four gateways at the rect edges, matching MapBuilder's path colours and
	-- the WorldLayout cross-zone directions.
	local edge = zone.Size.X / 2 - 4
	buildGateway(folder, "GatewaySouth", center + Vector3.new(0, groundY, -edge), Vector3.new(0, 0, -1), GATEWAY_COLORS.South, "HATCHERY")
	buildGateway(folder, "GatewayEast", center + Vector3.new(edge, groundY, 0), Vector3.new(1, 0, 0), GATEWAY_COLORS.East, "MARKET")
	buildGateway(folder, "GatewayWest", center + Vector3.new(-edge, groundY, 0), Vector3.new(-1, 0, 0), GATEWAY_COLORS.West, "HALL OF FAME")
	buildGateway(folder, "GatewayNorth", center + Vector3.new(0, groundY, edge), Vector3.new(0, 0, 1), GATEWAY_COLORS.North, "CTF ARENA")

	-- Corner gardens on the outer ring, in the four spots between gateways
	-- that were bare floor: a blossom tree, flower beds facing the plaza, and
	-- a balloon cluster. Softens the plaza for a young audience and gives the
	-- hub some green without touching any walking line (corners sit outside
	-- the mid ring, clear of the gateways, spawn and viewing deck).
	local cornerOffset = 63
	for i, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		local garden = WorldKit.Group(`CornerGarden{i}`, folder)
		local spot = center + corner * cornerOffset + Vector3.new(0, groundY, 0)
		local inward = -corner.Unit
		WorldKit.Tree({ Position = spot, Height = 13, Style = "Candy", Parent = garden })
		WorldKit.FlowerBed({ Position = spot + inward * 7 + Vector3.new(corner.Z * 3, 0, -corner.X * 3), Parent = garden })
		WorldKit.FlowerBed({ Position = spot + inward * 7 - Vector3.new(corner.Z * 3, 0, -corner.X * 3), Parent = garden })
		WorldKit.BalloonCluster({ Position = spot + corner.Unit * 6, Parent = garden })
	end
end

return HubZone
