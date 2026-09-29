--!strict
-- Fun Park: the playground. Everything here is about movement being fun on
-- its own, the way the most-played hangout games keep young players busy
-- between "real" objectives:
--   * jump pads that launch you onto a floating island (with a chest on it),
--   * trampolines you can chain-bounce between,
--   * a spiral obby tower with a reward chest at the top,
--   * an ice slide from the top of the tower back down to the entrance.
-- The loop is: arrive -> bounce -> climb -> claim -> slide -> repeat.
--
-- Pads and trampolines are tagged (Constants.TAGS) and driven client-side by
-- MovementController, so launches feel instant with no server round trip.
-- Chests are WorldKit.RewardChest props, driven by RewardChestService.
--
-- === Coordinate convention =================================================
-- WorldLayout.Get("FunPark") = Center (210, 0, 300), Size (130, 90, 140).
--   minX = 145, maxX = 275, minZ = 230, maxZ = 370.
-- The path from the Market District arrives on the south edge (Z = 230) at
-- X = 210; the entrance arch sits just inside it. West half (X < 215):
-- trampolines + jump pads + floating island. East half: obby tower centred
-- at (250, 335) with its slide running south down X = 250.
-- Heights: floor top = GroundY. Tower steps rise 3.3 studs each; the top
-- platform's walking surface is at GroundY + TOWER_TOP.
--
-- === Part budget =============================================================
-- Floor ~100 (TileSize 13), arch ~7, trampolines ~9, jump pads ~9, island ~6
-- + chest ~7, tower column 1 + 12 steps + top ~4 + chest ~7, slide ~5.
-- Roughly 180 parts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local FunParkZone = {}
FunParkZone.Order = 18

-- Candy palette: brighter and softer than the rest of the map on purpose -
-- the playground should read as "the fun place" from across the world.
local CANDY = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(120, 210, 255),
	Color3.fromRGB(255, 214, 90),
	Color3.fromRGB(140, 235, 150),
	Color3.fromRGB(190, 140, 255),
}
local DARK = Color3.fromRGB(34, 34, 48)

local TOWER_CENTER = Vector3.new(250, 0, 335)
local TOWER_TOP = 40
local STEP_COUNT = 12
local STEP_RISE = 3.3
local STEP_RADIUS = 12
local STEP_SIZE = 6.5

local function candy(i: number): Color3
	return CANDY[(i - 1) % #CANDY + 1]
end

local function buildTrampoline(folder: Instance, name: string, position: Vector3, color: Color3, power: number)
	-- Frame ring + a bouncy mat on top.
	WorldKit.UprightCylinder({
		Name = `{name}Frame`,
		Position = position + Vector3.new(0, 0.6, 0),
		Height = 1.2,
		Diameter = 11,
		Color = DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	local mat = WorldKit.UprightCylinder({
		Name = name,
		Position = position + Vector3.new(0, 1.3, 0),
		Height = 0.3,
		Diameter = 9.5,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	mat:SetAttribute("BouncePower", power)
	CollectionService:AddTag(mat, Constants.TAGS.Bouncy)
end

local function buildJumpPad(folder: Instance, name: string, position: Vector3, launch: Vector3)
	local pad = WorldKit.UprightCylinder({
		Name = name,
		Position = position + Vector3.new(0, 0.25, 0),
		Height = 0.5,
		Diameter = 6,
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	pad:SetAttribute("LaunchVelocity", launch)
	CollectionService:AddTag(pad, Constants.TAGS.JumpPad)
	WorldKit.UprightCylinder({
		Name = `{name}Rim`,
		Position = position + Vector3.new(0, 0.15, 0),
		Height = 0.3,
		Diameter = 7.2,
		Color = DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	WorldKit.Emitter({
		Name = `{name}Updraft`,
		Parent = pad,
		Color = Theme.Color.AccentPrimary,
		Rate = 6,
		Speed = NumberRange.new(6, 10),
		SpreadAngle = Vector2.new(8, 8),
	})
end

local function buildTower(folder: Instance)
	local groundY = WorldLayout.GroundY
	local base = Vector3.new(TOWER_CENTER.X, groundY, TOWER_CENTER.Z)

	-- Central column holding up the top platform.
	WorldKit.UprightCylinder({
		Name = "TowerColumn",
		Position = base + Vector3.new(0, TOWER_TOP / 2, 0),
		Height = TOWER_TOP - 1,
		Diameter = 6,
		Color = DARK,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})

	-- Spiral steps. Step 1 starts due north (the back of the tower, +Z) and
	-- climbs anticlockwise by 36 degrees per step, so the south side - where
	-- the slide leaves the top - is only passed by low steps (<= ~20 studs),
	-- leaving plenty of head room under the slide.
	for i = 1, STEP_COUNT do
		local angle = math.rad(90 + (i - 1) * 36)
		local topY = groundY + STEP_RISE * i
		local offset = Vector3.new(math.cos(angle) * STEP_RADIUS, 0, math.sin(angle) * STEP_RADIUS)
		WorldKit.Part({
			Name = `ObbyStep{i}`,
			Size = Vector3.new(STEP_SIZE, 1, STEP_SIZE),
			Position = base + offset + Vector3.new(0, topY - 0.5, 0),
			Color = candy(i),
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
	end

	-- A big friendly start marker at the foot of step 1.
	local startMarker = WorldKit.Part({
		Name = "ObbyStart",
		Size = Vector3.new(8, 0.3, 8),
		Position = base + Vector3.new(0, 0.15, STEP_RADIUS + 7), -- `base` already sits at GroundY
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = "ObbyStartSign",
		Adornee = startMarker,
		Text = "CLIMB! CHEST AT THE TOP",
		Color = Theme.Color.AccentPrimary,
		Size = UDim2.new(0, 300, 0, 48),
		TextSize = 24,
		StudsOffset = Vector3.new(0, 6, 0),
	})

	-- Top platform + railing + chest.
	local topCenter = base + Vector3.new(0, TOWER_TOP - 0.5, 0)
	WorldKit.Part({
		Name = "TowerTop",
		Size = Vector3.new(12, 1, 12),
		Position = topCenter,
		Color = Color3.fromRGB(255, 214, 90),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "TowerTopTrim",
		Width = 12,
		Depth = 12,
		Center = topCenter + Vector3.new(0, 0.6, 0),
		Color = Theme.Color.AccentWarning,
		Parent = folder,
	})
	WorldKit.RewardChest({
		ChestId = "ObbyTop",
		Label = "Obby Summit Chest",
		RewardCoins = 600,
		RewardXP = 150,
		CooldownSeconds = 10 * 60,
		Position = base + Vector3.new(0, TOWER_TOP, 3),
		Parent = folder,
	})

	-- Ice slide from the south edge of the top platform down to the ground,
	-- running south along X = TOWER_CENTER.X. Ice keeps friction low so it
	-- actually feels like sliding.
	local slideTop = Vector3.new(TOWER_CENTER.X, groundY + TOWER_TOP - 0.6, TOWER_CENTER.Z - 6)
	local slideBottom = Vector3.new(TOWER_CENTER.X, groundY - 0.3, TOWER_CENTER.Z - 86)
	local slideLength = (slideTop - slideBottom).Magnitude
	local slideCenter = (slideTop + slideBottom) / 2
	local slideFrame = CFrame.lookAt(slideCenter, slideTop)

	WorldKit.Part({
		Name = "IceSlide",
		Size = Vector3.new(7, 1, slideLength),
		CFrame = slideFrame,
		Color = Color3.fromRGB(170, 225, 255),
		Material = Enum.Material.Ice,
		Parent = folder,
	})
	for _, side in { 1, -1 } do
		WorldKit.Part({
			Name = `SlideRail{side}`,
			Size = Vector3.new(0.5, 1.4, slideLength),
			CFrame = slideFrame * CFrame.new(side * 3.7, 0.9, 0),
			Color = candy(side + 3),
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end
	-- Soft landing pad at the bottom.
	WorldKit.Part({
		Name = "SlideLanding",
		Size = Vector3.new(10, 0.4, 8),
		Position = Vector3.new(TOWER_CENTER.X, groundY + 0.2, slideBottom.Z - 3),
		Color = Color3.fromRGB(255, 120, 170),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
end

function FunParkZone.Build(parent: Instance)
	local zone = WorldLayout.Get("FunPark")
	local center = zone.Center
	local groundY = WorldLayout.GroundY
	local folder = WorldKit.Group("FunPark", parent)

	WorldKit.TiledFloor({
		Name = "FunParkFloor",
		Width = zone.Size.X,
		Depth = zone.Size.Z,
		TileSize = 13,
		Thickness = 1,
		Position = Vector3.new(center.X, groundY - 0.5, center.Z),
		ColorA = Color3.fromRGB(70, 60, 110),
		ColorB = Color3.fromRGB(56, 88, 120),
		Parent = folder,
	})

	-- Entrance arch on the south edge.
	local archZ = zone.Center.Z - zone.Size.Z / 2 + 5
	for i, side in { 1, -1 } do
		WorldKit.Pillar({
			Name = `EntrancePost{side}`,
			Position = Vector3.new(center.X + side * 11, groundY, archZ),
			Height = 13,
			Thickness = 2,
			Color = candy(i),
			CapColor = candy(i + 2),
			Parent = folder,
		})
	end
	local lintel = WorldKit.Part({
		Name = "EntranceLintel",
		Size = Vector3.new(26, 2.4, 2.4),
		Position = Vector3.new(center.X, groundY + 14.2, archZ),
		Color = Color3.fromRGB(255, 120, 170),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = "FunParkSign",
		Adornee = lintel,
		Text = "FUN PARK",
		Color = Color3.fromRGB(255, 214, 90),
		Size = UDim2.new(0, 260, 0, 64),
		StudsOffset = Vector3.new(0, 3.5, 0),
	})

	-- Trampolines in a zigzag so they can be chain-bounced.
	local trampolineSpots = {
		Vector3.new(170, groundY, 262),
		Vector3.new(186, groundY, 276),
		Vector3.new(170, groundY, 290),
		Vector3.new(186, groundY, 304),
	}
	for i, spot in trampolineSpots do
		buildTrampoline(folder, `Trampoline{i}`, spot, candy(i), 70 + i * 6)
	end

	-- Floating island, reached from the jump pads below it.
	local islandCenter = Vector3.new(165, groundY + 24, 340)
	WorldKit.Part({
		Name = "FloatingIsland",
		Size = Vector3.new(18, 2, 18),
		Position = islandCenter,
		Color = Color3.fromRGB(140, 235, 150),
		Material = Enum.Material.Grass,
		Parent = folder,
	})
	WorldKit.Part({
		Name = "IslandUnderside",
		Size = Vector3.new(14, 4, 14),
		Position = islandCenter - Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(110, 80, 60),
		Material = Enum.Material.Ground,
		Parent = folder,
	})
	WorldKit.RewardChest({
		ChestId = "SkyIsland",
		Label = "Sky Island Chest",
		RewardCoins = 250,
		RewardXP = 60,
		CooldownSeconds = 5 * 60,
		Position = islandCenter + Vector3.new(0, 1, 0),
		Parent = folder,
	})

	-- Jump pads south of the island, launching up and north onto it:
	-- ~100 studs/s up peaks ~25 studs, the northward push carries the player
	-- over the island edge. Players also have air control to correct.
	for i, x in { 157, 165, 173 } do
		buildJumpPad(folder, `JumpPad{i}`, Vector3.new(x, groundY, 318), Vector3.new(0, 100, 26))
	end

	buildTower(folder)
end

return FunParkZone
