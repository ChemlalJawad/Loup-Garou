--!strict
-- The Hatchery: the money-shot zone that sells "hatch eggs" as a loop. Three
-- egg podiums (Basic / Golden / Secret) escalate in height, glow and part
-- count so the Secret Egg reads as the prize before a player can afford it,
-- fronted by a five-station rarity showcase colonnade that teaches the
-- Common -> Secret color ladder (Constants.RARITY_ORDER / Theme.RarityColor)
-- at a glance. Purely atmospheric: the actual Egg screen opens from the HUD
-- nav dock regardless of where the player is standing (see DESIGN_SYSTEM.md).
--
-- === Coordinate convention =================================================
-- WorldLayout.Get("Hatchery") = Center (0, 0, -200), Size (150, 70, 130).
--   minX = -75, maxX = 75, minZ = -265, maxZ = -135.
-- +Z is "north", towards the Hub - MapBuilder's PathHubHatchery lands on our
-- maxZ edge (Z = -135), so that edge must stay clear. Every X/Z coordinate
-- below is written as an absolute number derived from those bounds (commented
-- inline) rather than hardcoded magic numbers. Every Y is derived
-- arithmetically from the part stacked directly beneath it - no floating
-- gaps, no coplanar faces.
--
-- === Part budget =============================================================
-- Floor ~80 (TiledFloor, TileSize 14 to stay cheap over a 140x120 footprint),
-- entrance gate ~4, rarity colonnade ~20 (+ up to ~60 more if BrainrotModels
-- statues are available), egg podiums ~36, hall shell (pillars/roof/walls)
-- ~20. Total roughly 160-220 parts, comfortably under the ~350/zone budget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

-- BrainrotModels is owned by a parallel agent (Shared/Brainrots/BrainrotModels.lua)
-- and may not exist yet at the time this file is authored/built. pcall the
-- require so its absence never hard-errors the zone (per EXPANSION_PLAN.md).
local BrainrotModelsOk, BrainrotModels = pcall(function()
	return require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
end)
if not BrainrotModelsOk then
	BrainrotModels = nil
end

local HatcheryZone = { Order = 15 }

local ZONE_ID = "Hatchery"

-- One representative roster id per rarity (docs/BRAINROT_ROSTER.md), used to
-- populate the rarity showcase plinths when BrainrotModels is available.
local SHOWCASE_CHARACTER_BY_RARITY: { [string]: string } = {
	Common = "Spaghettoro",
	Rare = "GirafferroEspressone",
	Epic = "FenicotteroPizzaiolo",
	Legendary = "CrocobrividoVulcanico",
	Secret = "TralaleroAstrale",
}

-- Non-token colors below (eggshell cream, marbled basic-tier accents) are
-- deliberately new values, not restatements of an existing Theme token.
local BASIC_SHELL_COLOR = Color3.fromRGB(224, 214, 196)
local BASIC_SPOT_COLOR = Color3.fromRGB(196, 182, 158)
local GOLDEN_SPOT_COLOR = Color3.fromRGB(255, 214, 140)

-- Places a small SurfaceLabel plaque in front of `attachTo`, standing on the
-- floor at `position` (a ground-level point; the plaque itself is a stubby
-- vertical board so the label reads upright).
local function buildPlaque(parent: Instance, name: string, position: Vector3, text: string, color: Color3)
	local plaque = WorldKit.Part({
		Name = name,
		Size = Vector3.new(3.2, 1.6, 0.3),
		Position = position + Vector3.new(0, 0.8, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
	WorldKit.SurfaceLabel({
		Adornee = plaque,
		Name = "Label",
		Text = text,
		Color = color,
		Face = Enum.NormalId.Front,
		CanvasSize = Vector2.new(200, 100),
		Parent = plaque,
	})
	return plaque
end

-- === Rarity showcase colonnade =============================================
-- Five stations, one per Constants.RARITY_ORDER, spread across the width of
-- the hall just past the entrance. Each is a pillar capped in that rarity's
-- color, a plinth, an optional Brainrot statue, and a naming plaque - the
-- same "more glow = rarer" teaching device the hatch-reveal UI already uses.
local function buildRarityColonnade(parent: Instance, rowZ: number)
	local folder = WorldKit.Group("RarityColonnade", parent)
	local rarities = Constants.RARITY_ORDER -- { Common, Rare, Epic, Legendary, Secret }
	local count = #rarities
	local spacing = 30 -- studs between station centers
	local startX = -((count - 1) / 2) * spacing -- centers the row on X = 0

	for i, rarity in rarities do
		local x = startX + (i - 1) * spacing
		local color = Theme.RarityColor(rarity)

		-- Pillar with a glowing cap in the rarity color (WorldKit.Pillar adds
		-- the cap part itself when CapColor is provided).
		WorldKit.Pillar({
			Name = `RarityPillar_{rarity}`,
			Position = Vector3.new(x, 0, rowZ),
			Height = 10,
			Thickness = 2,
			Color = Theme.Color.Surface,
			CapColor = color,
			Parent = folder,
		})

		-- Plinth: a low cylinder standing 3 studs in front of the pillar
		-- (further from the back wall, closer to the walking path) so a
		-- statue on top reads clearly against the pillar behind it.
		local plinthDiameter = 6
		local plinthHeight = 2
		local plinthCenter = Vector3.new(x, plinthHeight / 2, rowZ + 3)
		WorldKit.UprightCylinder({
			Name = `RarityPlinth_{rarity}`,
			Position = plinthCenter,
			Diameter = plinthDiameter,
			Height = plinthHeight,
			Color = Theme.Color.SurfaceRaised,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
		WorldKit.NeonBorder({
			Name = `RarityPlinthTrim_{rarity}`,
			Center = plinthCenter + Vector3.new(0, plinthHeight / 2 + 0.05, 0),
			Width = plinthDiameter + 0.4,
			Depth = plinthDiameter + 0.4,
			Thickness = 0.4,
			Height = 0.15,
			Color = color,
			Parent = folder,
		})

		local plinthTopY = plinthHeight -- top surface of the plinth

		-- Statue if BrainrotModels is available; otherwise an abstract
		-- rarity-colored form so the station never reads as broken/empty.
		local characterId = SHOWCASE_CHARACTER_BY_RARITY[rarity]
		local placed = false
		if BrainrotModels and characterId then
			local ok, model = pcall(function()
				return (BrainrotModels :: any).BuildStatic(characterId, rarity)
			end)
			if ok and model then
				model.Parent = folder
				-- BrainrotModels' local convention: feet/underside sit at
				-- local Y = 0, so pivoting to plinthTopY lands them exactly
				-- on the plinth surface.
				model:PivotTo(CFrame.new(x, plinthTopY, rowZ + 3) * CFrame.Angles(0, math.rad(180), 0))
				placed = true
			end
		end
		if not placed then
			WorldKit.Sphere({
				Name = `RarityAbstract_{rarity}`,
				Diameter = 3,
				Position = Vector3.new(x, plinthTopY + 1.5, rowZ + 3),
				Color = color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = folder,
			})
		end

		WorldKit.Light({
			Name = `RarityLight_{rarity}`,
			Color = color,
			Brightness = 2,
			Range = 16,
			Parent = folder.Parent and (folder:FindFirstChild(`RarityPillar_{rarity}Cap`) or plinthDiameter and folder) or folder,
		})

		buildPlaque(folder, `RarityPlaque_{rarity}`, Vector3.new(x, 0, rowZ + 6.5), string.upper(rarity), color)
	end

	return folder
end

-- === Egg podiums =============================================================

type EggSpec = {
	Name: string,
	Position: Vector3, -- ground-level center (Y = 0, the floor top)
	BaseDiameter: number,
	BaseHeight: number,
	SecondDiameter: number?, -- optional second wedding-cake tier
	SecondHeight: number?,
	EggWidth: number,
	EggHeight: number,
	ShellColor: Color3,
	AccentColor: Color3,
	Material: Enum.Material,
	LightBrightness: number,
	LightRange: number,
	Emitter: boolean,
	Label: string,
}

local function buildEggPodium(parent: Instance, spec: EggSpec)
	local folder = WorldKit.Group(spec.Name, parent)
	local baseX, baseZ = spec.Position.X, spec.Position.Z

	-- Tier 1 (bottom) cylinder: bottom sits on the floor (Y = 0).
	local tier1Top = spec.BaseHeight
	WorldKit.UprightCylinder({
		Name = spec.Name .. "_Base1",
		Position = Vector3.new(baseX, spec.BaseHeight / 2, baseZ),
		Diameter = spec.BaseDiameter,
		Height = spec.BaseHeight,
		Color = Theme.Color.Surface,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = spec.Name .. "_Base1Trim",
		Center = Vector3.new(baseX, tier1Top + 0.05, baseZ),
		Width = spec.BaseDiameter + 0.6,
		Depth = spec.BaseDiameter + 0.6,
		Thickness = 0.5,
		Height = 0.2,
		Color = spec.AccentColor,
		Parent = folder,
	})

	-- Optional tier 2 (wedding-cake step, used by the Secret podium): bottom
	-- of tier 2 = top of tier 1, arithmetically, no floating gap.
	local platformTopY = tier1Top
	if spec.SecondDiameter and spec.SecondHeight then
		local tier2Height = spec.SecondHeight
		local tier2CenterY = tier1Top + tier2Height / 2
		WorldKit.UprightCylinder({
			Name = spec.Name .. "_Base2",
			Position = Vector3.new(baseX, tier2CenterY, baseZ),
			Diameter = spec.SecondDiameter,
			Height = tier2Height,
			Color = Theme.Color.SurfaceRaised,
			Material = Enum.Material.Concrete,
			Parent = folder,
		})
		platformTopY = tier1Top + tier2Height
		WorldKit.NeonBorder({
			Name = spec.Name .. "_Base2Trim",
			Center = Vector3.new(baseX, platformTopY + 0.05, baseZ),
			Width = spec.SecondDiameter + 0.6,
			Depth = spec.SecondDiameter + 0.6,
			Thickness = 0.5,
			Height = 0.2,
			Color = spec.AccentColor,
			Parent = folder,
		})
	end

	-- The egg itself: a single non-uniform Ball part (ovoid), bottom resting
	-- on the platform top, arithmetically stacked.
	local eggCenterY = platformTopY + spec.EggHeight / 2
	local egg = WorldKit.Part({
		Name = spec.Name .. "_Egg",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(spec.EggWidth, spec.EggHeight, spec.EggWidth),
		Position = Vector3.new(baseX, eggCenterY, baseZ),
		Color = spec.ShellColor,
		Material = spec.Material,
		CanCollide = false,
		Parent = folder,
	})

	-- A few small accent spots for surface texture/detail (speckles), welded
	-- visually by simple positioning (no physics needed, everything anchored).
	local spotOffsets = {
		Vector3.new(spec.EggWidth * 0.28, spec.EggHeight * 0.18, spec.EggWidth * 0.2),
		Vector3.new(-spec.EggWidth * 0.24, -spec.EggHeight * 0.1, spec.EggWidth * 0.26),
		Vector3.new(spec.EggWidth * 0.1, spec.EggHeight * 0.3, -spec.EggWidth * 0.28),
	}
	for i, offset in spotOffsets do
		WorldKit.Sphere({
			Name = `{spec.Name}_Spot{i}`,
			Diameter = spec.EggWidth * 0.16,
			Position = Vector3.new(baseX, eggCenterY, baseZ) + offset,
			Color = spec.AccentColor,
			Material = spec.Material == Enum.Material.Neon and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = folder,
		})
	end

	WorldKit.Light({
		Name = spec.Name .. "_Light",
		Color = spec.AccentColor,
		Brightness = spec.LightBrightness,
		Range = spec.LightRange,
		Parent = egg,
	})

	if spec.Emitter then
		WorldKit.Emitter({
			Name = spec.Name .. "_Sparkle",
			Color = spec.AccentColor,
			Rate = 12,
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(180, 180),
			Parent = egg,
		})
	end

	buildPlaque(folder, spec.Name .. "_Plaque", Vector3.new(baseX, 0, baseZ + spec.BaseDiameter / 2 + 4), spec.Label, spec.AccentColor)

	return eggCenterY + spec.EggHeight / 2 -- top of the egg, for callers that want it
end

-- === Covered hall shell ======================================================
-- Cheap "reads as a building, not props on grass" cover: side pillars, a flat
-- roof slab, and a back wall with an arched glow behind the Secret podium.
local function buildHallShell(parent: Instance, zone: WorldLayout.ZoneRect)
	local folder = WorldKit.Group("HallShell", parent)
	local minX = zone.Center.X - zone.Size.X / 2 -- -75
	local maxX = zone.Center.X + zone.Size.X / 2 -- 75
	local minZ = zone.Center.Z - zone.Size.Z / 2 -- -265
	local roofHeight = 18

	-- Side pillars along both long walls, from just past the colonnade to
	-- near the back wall.
	local pillarZs = { -215, -195, -175 } -- studs; within [minZ+? , maxZ-?]
	for _, z in pillarZs do
		for _, x in { minX + 4, maxX - 4 } do
			WorldKit.Pillar({
				Name = `HallPillar_{x}_{z}`,
				Position = Vector3.new(x, 0, z),
				Height = roofHeight,
				Thickness = 2.4,
				Color = Theme.Color.Surface,
				CapColor = Theme.Color.AccentSecondary,
				Parent = folder,
			})
		end
	end

	-- Flat roof slab spanning the hall (from the colonnade back to the rear
	-- wall), sitting on top of the pillars.
	local roofDepth = 110 -- covers Z in [-265, -155]
	local roofCenterZ = minZ + roofDepth / 2 -- -265 + 55 = -210
	WorldKit.Part({
		Name = "RoofSlab",
		Size = Vector3.new(zone.Size.X - 4, 1, roofDepth),
		Position = Vector3.new(zone.Center.X, roofHeight + 0.5, roofCenterZ),
		Color = Theme.Color.Background,
		Material = Enum.Material.Concrete,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "RoofTrim",
		Center = Vector3.new(zone.Center.X, roofHeight, roofCenterZ),
		Width = zone.Size.X - 4,
		Depth = roofDepth,
		Thickness = 0.6,
		Height = 0.3,
		Color = Theme.Color.AccentSecondary,
		Parent = folder,
	})

	-- Rear wall behind the Secret podium, with a purple-lit "apse" glow.
	WorldKit.Wall({
		Name = "RearWall",
		Size = Vector3.new(zone.Size.X - 4, roofHeight, 1),
		Position = Vector3.new(zone.Center.X, roofHeight / 2, minZ + 2),
		Color = Theme.Color.Surface,
		TrimColor = Theme.Color.AccentSecondary,
		Parent = folder,
	})

	-- Side walls (low, mostly implied openness so the hall doesn't feel
	-- boxed-in from the walking path).
	for _, x in { minX + 1, maxX - 1 } do
		WorldKit.Wall({
			Name = `SideWall_{x}`,
			Size = Vector3.new(1, roofHeight * 0.55, roofDepth),
			Position = Vector3.new(x, roofHeight * 0.275, roofCenterZ),
			Color = Theme.Color.Surface,
			TrimColor = Theme.Color.AccentSecondary,
			Parent = folder,
		})
	end

	return folder
end

function HatcheryZone.Build(parent: Instance)
	local zone = WorldLayout.Get(ZONE_ID)
	local minX = zone.Center.X - zone.Size.X / 2 -- -75
	local maxX = zone.Center.X + zone.Size.X / 2 -- 75
	local minZ = zone.Center.Z - zone.Size.Z / 2 -- -265
	local maxZ = zone.Center.Z + zone.Size.Z / 2 -- -135 (entrance edge, +Z toward Hub)

	local hatchery = WorldKit.Group("Hatchery", parent)

	-- Floor: 140x120 footprint (5-stud margin inside the 150x130 rect on
	-- every side) at TileSize 14 -> 10x8 = 80 tiles. Top surface sits at
	-- GroundY (0), so the tile's Y center is -0.5 (thickness 1, top = center
	-- + 0.5).
	WorldKit.TiledFloor({
		Name = "HatcheryFloor",
		Width = 140,
		Depth = 120,
		TileSize = 14,
		Position = Vector3.new(zone.Center.X, WorldLayout.GroundY - 0.5, zone.Center.Z),
		ColorA = Theme.Color.Surface,
		ColorB = Theme.Color.SurfaceRaised,
		Parent = hatchery,
	})

	-- Entrance gate: two low pylons flanking the 14-stud-wide path at the
	-- north (+Z) edge, well clear of the path itself (path spans X in
	-- [-7, 7]; pylons sit outside that at X = +-9).
	local gateZ = maxZ - 3 -- -138, just inside our rect from the maxZ edge
	for _, x in { -9, 9 } do
		WorldKit.Pillar({
			Name = `GatePylon_{x}`,
			Position = Vector3.new(x, 0, gateZ),
			Height = 10,
			Thickness = 2.2,
			Color = Theme.Color.Surface,
			CapColor = Theme.Color.AccentSecondary,
			Parent = hatchery,
		})
	end
	WorldKit.Sign({
		Name = "HatcheryEntranceSign",
		Adornee = hatchery:FindFirstChild("GatePylon_9"),
		Text = "HATCHERY",
		Color = Theme.Color.AccentSecondary,
		StudsOffset = Vector3.new(-9, 5, 0),
		Size = UDim2.new(0, 280, 0, 70),
		Parent = hatchery,
	})

	-- Rarity showcase colonnade, just past the entrance apron.
	buildRarityColonnade(hatchery, -165) -- Z = -165, inside [minZ, maxZ]

	-- Three egg podiums on an ascending arc: Basic (front/side, lowest),
	-- Golden (mid, taller), Secret (back/center, tallest + most FX). Each
	-- podium's Z keeps at least 12 studs of clearance from its neighbors and
	-- from the rear wall (minZ = -265) / colonnade (Z = -165).
	buildEggPodium(hatchery, {
		Name = "BasicEggPodium",
		Position = Vector3.new(-32, 0, -188), -- front-left of the hall
		BaseDiameter = 14,
		BaseHeight = 2,
		EggWidth = 5,
		EggHeight = 7,
		ShellColor = BASIC_SHELL_COLOR,
		AccentColor = BASIC_SPOT_COLOR,
		Material = Enum.Material.SmoothPlastic,
		LightBrightness = 1.5,
		LightRange = 10,
		Emitter = false,
		Label = "BASIC EGG",
	})

	buildEggPodium(hatchery, {
		Name = "GoldenEggPodium",
		Position = Vector3.new(30, 0, -208), -- front-right, slightly deeper
		BaseDiameter = 16,
		BaseHeight = 4,
		EggWidth = 6.5,
		EggHeight = 9,
		ShellColor = Theme.Rarity.Legendary, -- gold, reused deliberately for "golden" identity
		AccentColor = GOLDEN_SPOT_COLOR,
		Material = Enum.Material.Neon,
		LightBrightness = 2.5,
		LightRange = 18,
		Emitter = false,
		Label = "GOLDEN EGG",
	})

	buildEggPodium(hatchery, {
		Name = "SecretEggPodium",
		Position = Vector3.new(0, 0, -244), -- dead-center, deepest into the hall, under the apse
		BaseDiameter = 20,
		BaseHeight = 3,
		SecondDiameter = 14,
		SecondHeight = 4,
		EggWidth = 8.5,
		EggHeight = 12,
		ShellColor = Theme.Color.AccentSecondary, -- purple, hatchery's premium trim color
		AccentColor = Theme.Rarity.Secret, -- pink, the Secret rarity token
		Material = Enum.Material.Neon,
		LightBrightness = 4.5,
		LightRange = 32,
		Emitter = true,
		Label = "SECRET EGG",
	})

	-- Covered hall shell around the podiums so this reads as a building.
	buildHallShell(hatchery, zone)

	assert(minX and maxX, "HatcheryZone: bounds computed") -- silence unused warnings on strict builds
end

return HatcheryZone
