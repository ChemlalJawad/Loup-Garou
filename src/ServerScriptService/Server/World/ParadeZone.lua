--!strict
-- Brainrot Parade: a red carpet runway where Brainrots walk from a glowing
-- start portal to an exit arch, and players shop from the open plaza beside
-- it. This module only builds the stage; ParadeService/ParadeController run
-- the walkers. The carpet line comes from ParadeConfig.CarpetEndpoints() so
-- the geometry and the walkers can never disagree about where the carpet is.
--
-- === Coordinate convention =================================================
-- WorldLayout.Get("Parade") = Center (-210, 0, -200), Size (140, 60, 130).
--   minX = -280, maxX = -140, minZ = -265, maxZ = -135.
-- The carpet runs west -> east at Z = -218 (ParadeConfig.CARPET_Z_OFFSET).
-- North of it (Z -212 .. -135) is the open shopping plaza; the path from the
-- Hall of Fame lands on the north edge at X = -210, and the path to the
-- Hatchery leaves the east edge at Z = WorldLayout.Doors.HatcheryWest.Z
-- (-205). Both stay clear. South of the carpet is the backdrop.
--
-- Y stacking: floor tiles top at GroundY; carpet (0.6 thick) sits on them,
-- top = ParadeConfig.CARPET_TOP_Y. Walls/posts stand on GroundY.
--
-- === Part budget =============================================================
-- Floor ~90 (TileSize 14), carpet + trims 3, gates ~16, backdrop ~26,
-- rope posts ~15, info boards ~6, benches ~8. Roughly 165 parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local ParadeConfig = require(ReplicatedStorage.Shared.Parade.ParadeConfig)
local Mutations = require(ReplicatedStorage.Shared.Brainrots.Mutations)
local WorldKit = require(script.Parent.WorldKit)

local ParadeZone = {}
ParadeZone.Order = 17

local CARPET_RED = Color3.fromRGB(196, 28, 48)
local VELVET = Color3.fromRGB(120, 16, 32)
local GOLD = Color3.fromRGB(255, 196, 70)
local STAGE_DARK = Color3.fromRGB(26, 22, 34)

local function buildGate(folder: Instance, name: string, center: Vector3, width: number, height: number, color: Color3, label: string)
	for _, side in { 1, -1 } do
		WorldKit.Pillar({
			Name = `{name}Post{side}`,
			Position = center + Vector3.new(0, 0, side * width / 2),
			Height = height,
			Thickness = 1.8,
			Color = STAGE_DARK,
			CapColor = color,
			Parent = folder,
		})
	end
	local lintel = WorldKit.Part({
		Name = `{name}Lintel`,
		Size = Vector3.new(2, 2.4, width + 2),
		Position = center + Vector3.new(0, height + 1.2, 0),
		Color = STAGE_DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	WorldKit.Part({
		Name = `{name}LintelGlow`,
		Size = Vector3.new(2.2, 0.4, width + 2.2),
		Position = center + Vector3.new(0, height + 0.1, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = `{name}Sign`,
		Adornee = lintel,
		Text = label,
		Color = color,
		Size = UDim2.new(0, 280, 0, 56),
		StudsOffset = Vector3.new(0, 3, 0),
	})
	return lintel
end

-- A flat info board facing north (+Z, the direction players arrive from),
-- so "what does it cost / what's a mutation" is answered before a young
-- player has to ask.
local function buildInfoBoard(folder: Instance, name: string, position: Vector3, text: string, accent: Color3)
	WorldKit.Part({
		Name = `{name}Post`,
		Size = Vector3.new(0.8, 6, 0.8),
		Position = position + Vector3.new(0, 3, 0),
		Color = STAGE_DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	local board = WorldKit.Part({
		Name = name,
		Size = Vector3.new(18, 7, 0.6),
		Position = position + Vector3.new(0, 9.5, 0),
		Color = STAGE_DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	WorldKit.Part({
		Name = `{name}Trim`,
		Size = Vector3.new(18.4, 0.3, 0.7),
		Position = position + Vector3.new(0, 13.1, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.SurfaceLabel({
		Name = `{name}Text`,
		Adornee = board,
		Face = Enum.NormalId.Back, -- +Z: toward arriving players
		CanvasSize = Vector2.new(720, 280),
		Text = text,
		Color = Theme.Color.TextPrimary,
	})
end

function ParadeZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Parade")
	local center = zone.Center
	local groundY = WorldLayout.GroundY
	local folder = WorldKit.Group("Parade", parent)

	WorldKit.TiledFloor({
		Name = "ParadeFloor",
		Width = zone.Size.X,
		Depth = zone.Size.Z,
		TileSize = 14,
		Thickness = 1,
		Position = Vector3.new(center.X, groundY - 0.5, center.Z),
		ColorA = Color3.fromRGB(34, 28, 40),
		ColorB = Color3.fromRGB(42, 34, 50),
		Parent = folder,
	})

	-- Carpet -----------------------------------------------------------------
	local startPoint, endPoint = ParadeConfig.CarpetEndpoints()
	local carpetLength = (endPoint - startPoint).Magnitude + 6
	local carpetCenter = (startPoint + endPoint) / 2
	local carpetThickness = ParadeConfig.CARPET_TOP_Y - groundY
	local carpetWidth = ParadeConfig.CARPET_WIDTH

	WorldKit.Part({
		Name = "RedCarpet",
		Size = Vector3.new(carpetLength, carpetThickness, carpetWidth),
		Position = Vector3.new(carpetCenter.X, groundY + carpetThickness / 2, carpetCenter.Z),
		Color = CARPET_RED,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	for _, side in { 1, -1 } do
		WorldKit.Part({
			Name = `CarpetEdge{side}`,
			Size = Vector3.new(carpetLength, 0.2, 0.5),
			Position = Vector3.new(carpetCenter.X, ParadeConfig.CARPET_TOP_Y + 0.1, carpetCenter.Z + side * (carpetWidth / 2 - 0.25)),
			Color = GOLD,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	-- Start portal: a tunnel the Brainrots emerge from, with a glowing mouth.
	local portalX = startPoint.X - 1
	local portal = buildGate(
		folder,
		"StartPortal",
		Vector3.new(portalX, groundY, startPoint.Z),
		carpetWidth + 3,
		12,
		Theme.Color.AccentSecondary,
		"BRAINROT PARADE"
	)
	WorldKit.Part({
		Name = "PortalVeil",
		Size = Vector3.new(0.4, 11.5, carpetWidth + 1.2),
		Position = Vector3.new(portalX - 0.6, groundY + 5.75, startPoint.Z),
		Color = Theme.Color.AccentSecondary,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.Emitter({
		Name = "PortalSparkles",
		Parent = portal,
		Color = Theme.Color.AccentSecondary,
		Rate = 10,
		SpreadAngle = Vector2.new(60, 60),
	})
	-- Tunnel box behind the portal so walkers visibly come *out of* somewhere.
	local tunnelLength = 10
	local tunnelCenterX = portalX - tunnelLength / 2 - 1
	WorldKit.Part({
		Name = "TunnelRoof",
		Size = Vector3.new(tunnelLength, 1, carpetWidth + 4),
		Position = Vector3.new(tunnelCenterX, groundY + 12.5, startPoint.Z),
		Color = STAGE_DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	for _, side in { 1, -1 } do
		WorldKit.Wall({
			Name = `TunnelWall{side}`,
			Size = Vector3.new(tunnelLength, 12, 1),
			Position = Vector3.new(tunnelCenterX, groundY + 6, startPoint.Z + side * (carpetWidth / 2 + 2)),
			Color = STAGE_DARK,
			TrimColor = Theme.Color.AccentSecondary,
			Parent = folder,
		})
	end

	-- Exit arch.
	buildGate(
		folder,
		"ExitArch",
		Vector3.new(endPoint.X + 1, groundY, endPoint.Z),
		carpetWidth + 3,
		10,
		GOLD,
		"EXIT"
	)

	-- Backdrop: a stage wall south of the carpet with spotlights and banners
	-- in every rarity colour - it frames the carpet like a real runway.
	local backdropZ = startPoint.Z - carpetWidth / 2 - 5
	local backdropLength = zone.Size.X - 8
	WorldKit.Wall({
		Name = "Backdrop",
		Size = Vector3.new(backdropLength, 14, 1.2),
		Position = Vector3.new(center.X, groundY + 7, backdropZ),
		Color = VELVET,
		TrimColor = GOLD,
		Parent = folder,
	})

	local rarityColors = {
		Theme.Rarity.Common,
		Theme.Rarity.Rare,
		Theme.Rarity.Epic,
		Theme.Rarity.Legendary,
		Theme.Rarity.Secret,
	}
	local spotCount = 8
	for i = 1, spotCount do
		local t = (i - 0.5) / spotCount
		local x = center.X - backdropLength / 2 + backdropLength * t
		local color = rarityColors[(i - 1) % #rarityColors + 1]
		local spot = WorldKit.Part({
			Name = `Spotlight{i}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = Vector3.new(x, groundY + 12, backdropZ + 1.4),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		WorldKit.Light({
			Name = "SpotGlow",
			Color = color,
			Brightness = 2.2,
			Range = 16,
			Parent = spot,
		})
		-- Hanging banner below every other spotlight.
		if i % 2 == 1 then
			WorldKit.Part({
				Name = `Banner{i}`,
				Size = Vector3.new(3, 7, 0.2),
				Position = Vector3.new(x, groundY + 6.5, backdropZ + 0.8),
				Color = color,
				Material = Enum.Material.Fabric,
				CanCollide = false,
				Parent = folder,
			})
		end
	end

	-- Velvet-rope posts along the shopping side of the carpet. Purely
	-- decorative and non-colliding: kids can (and will) run along the carpet
	-- with the Brainrots, and that should be allowed.
	local ropeZ = startPoint.Z + carpetWidth / 2 + 1.2
	local postCount = 14
	for i = 1, postCount do
		local t = (i - 0.5) / postCount
		local x = startPoint.X + (endPoint.X - startPoint.X) * t
		WorldKit.Part({
			Name = `RopePost{i}`,
			Size = Vector3.new(0.5, 3, 0.5),
			Position = Vector3.new(x, groundY + 1.5, ropeZ),
			Color = GOLD,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = folder,
		})
	end

	-- Info boards near the north entrance.
	local priceLines = {}
	for _, rarity in ParadeConfig.RarityOrder do
		table.insert(priceLines, `{rarity}: {ParadeConfig.FormatCoins(ParadeConfig.BasePrice[rarity])}`)
	end
	buildInfoBoard(
		folder,
		"PriceBoard",
		Vector3.new(center.X - 24, groundY, zone.Center.Z + zone.Size.Z / 2 - 16),
		"PARADE PRICES\n" .. table.concat(priceLines, "   "),
		GOLD
	)

	local mutationLines = {}
	for _, mutationId in { "Gold", "Diamond", "Galaxy", "Rainbow" } do
		local def = Mutations.Get(mutationId)
		if def then
			local suffix = if def.NightOnly then " (night)" else ""
			table.insert(mutationLines, `{def.DisplayName} x{def.IncomeMultiplier}{suffix}`)
		end
	end
	buildInfoBoard(
		folder,
		"MutationBoard",
		Vector3.new(center.X + 24, groundY, zone.Center.Z + zone.Size.Z / 2 - 16),
		"MUTATIONS = MORE COINS\n" .. table.concat(mutationLines, "   "),
		Theme.Color.AccentSecondary
	)

	-- A secret chest backstage, behind the east end of the backdrop: nothing
	-- points to it, which is the point. Finding hidden treasure is one of the
	-- most reliably fun things for young players, and word-of-mouth ("there's
	-- a chest behind the Parade!") is free marketing.
	WorldKit.RewardChest({
		ChestId = "BackstageSecret",
		Label = "Backstage Secret Chest",
		RewardCoins = 180,
		RewardXP = 40,
		CooldownSeconds = 20 * 60,
		Position = Vector3.new(center.X + 52, groundY, backdropZ - 9),
		Rotation = CFrame.Angles(0, math.pi, 0),
		Parent = folder,
	})

	-- A couple of benches facing the carpet for watching the show.
	for i, x in { center.X - 40, center.X - 10, center.X + 20, center.X + 45 } do
		WorldKit.Part({
			Name = `Bench{i}`,
			Size = Vector3.new(7, 1.2, 1.8),
			Position = Vector3.new(x, groundY + 0.6, ropeZ + 14),
			Color = Color3.fromRGB(90, 60, 40),
			Material = Enum.Material.WoodPlanks,
			Parent = folder,
		})
		WorldKit.Part({
			Name = `BenchBack{i}`,
			Size = Vector3.new(7, 1.6, 0.4),
			Position = Vector3.new(x, groundY + 1.8, ropeZ + 14.9),
			Color = Color3.fromRGB(90, 60, 40),
			Material = Enum.Material.WoodPlanks,
			Parent = folder,
		})
	end
end

return ParadeZone
