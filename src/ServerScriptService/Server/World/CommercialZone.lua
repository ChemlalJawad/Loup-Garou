--!strict
-- Market District: a short commercial street with two storefronts fronting
-- the game's two purchase screens. Purely atmospheric - the STORE (in-game
-- currency) and SHOP (Robux) panels both open from the HUD nav dock
-- regardless of where the player is standing; this zone just gives those
-- activities a place in the world.
--
-- === Coordinate convention =================================================
-- WorldLayout.Get("Commercial") = Center (210, 0, 0), Size (140, 70, 150).
--   minX = 140, maxX = 280, minZ = -75, maxZ = 75.
-- -X is "west", towards the Hub - MapBuilder's PathHubCommercial lands on our
-- minX edge (X = 140), so that edge must stay clear as the street's entrance.
-- -Z is "south", towards the Lounge - PathCommercialLounge lands on our minZ
-- edge (Z = -75), so that edge stays clear too. The street therefore runs
-- roughly north-south with the entrance at the west end, walkable spine
-- continuing south to the Lounge connector.
-- Every Y is derived arithmetically from the part stacked directly beneath
-- it - no floating gaps, no coplanar z-fighting.
--
-- === Part budget =============================================================
-- Floor ~40 (TiledFloor, TileSize 14 over 130x140), two storefronts ~30 each,
-- street dressing (lamp posts, stalls, planters, banners) ~60, entrance arch
-- ~6. Total roughly 190 parts, comfortably under the ~350/zone budget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local CommercialZone = {}
CommercialZone.Order = 13

local STONE = Color3.fromRGB(28, 28, 40)
local STONE_LIGHT = Color3.fromRGB(38, 38, 54)

-- A storefront: raised platform, back/side walls, an awning over the front
-- door, a lit sign, and a couple of display-window strips. `facing` is the
-- unit-ish direction the front door opens toward (street-facing).
local function buildStorefront(folder: Instance, name: string, center: Vector3, groundY: number, accent: Color3, label: string, facing: Vector3)
	local width, depth, wallHeight = 24, 20, 12
	local faceAxis = if math.abs(facing.X) > math.abs(facing.Z) then "X" else "Z"

	WorldKit.Part({
		Name = `{name}Platform`,
		Size = Vector3.new(width, 1, depth),
		Position = center + Vector3.new(0, groundY + 0.5, 0),
		Color = STONE_LIGHT,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = `{name}PlatformTrim`,
		Width = width,
		Depth = depth,
		Center = center + Vector3.new(0, groundY + 1.05, 0),
		Color = accent,
		Parent = folder,
	})

	-- Back wall (opposite the facing direction) and two side walls; the
	-- facing edge stays open as the storefront's "door".
	local backOffset = -facing * (if faceAxis == "X" then width / 2 - 0.75 else depth / 2 - 0.75)
	WorldKit.Wall({
		Name = `{name}BackWall`,
		Size = if faceAxis == "X" then Vector3.new(1.5, wallHeight, depth) else Vector3.new(width, wallHeight, 1.5),
		Position = center + backOffset + Vector3.new(0, groundY + 1 + wallHeight / 2, 0),
		Color = STONE,
		TrimColor = accent,
		Parent = folder,
	})
	local sideSpan = if faceAxis == "X" then depth else width
	local sideAxisVector = if faceAxis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	for _, sign in { 1, -1 } do
		WorldKit.Wall({
			Name = `{name}SideWall{sign}`,
			Size = if faceAxis == "X" then Vector3.new(width * 0.7, wallHeight, 1.5) else Vector3.new(1.5, wallHeight, depth * 0.7),
			Position = center + sideAxisVector * (sideSpan / 2 - 0.75) * sign + Vector3.new(0, groundY + 1 + wallHeight / 2, 0),
			Color = STONE,
			Parent = folder,
		})
	end

	-- Awning: a slanted wedge over the doorway, plus two support poles.
	local doorOffset = facing * (if faceAxis == "X" then width / 2 else depth / 2)
	local awningCenter = center + doorOffset * 0.85 + Vector3.new(0, groundY + 1 + wallHeight * 0.7, 0)
	WorldKit.Wedge({
		Name = `{name}Awning`,
		Size = Vector3.new(if faceAxis == "X" then 6 else width * 0.8, 3, if faceAxis == "X" then depth * 0.8 else 6),
		Position = awningCenter,
		Rotation = if faceAxis == "X"
			then CFrame.Angles(0, 0, math.rad(if facing.X > 0 then -90 else 90))
			else CFrame.Angles(math.rad(if facing.Z > 0 then 90 else -90), 0, 0),
		Color = accent,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = folder,
	})

	-- Display window strips flanking the door, glowing faintly.
	for _, sign in { 1, -1 } do
		WorldKit.Part({
			Name = `{name}Window{sign}`,
			Size = if faceAxis == "X" then Vector3.new(0.4, 4, 6) else Vector3.new(6, 4, 0.4),
			Position = center
				+ doorOffset
				+ sideAxisVector * (sideSpan * 0.28) * sign
				+ Vector3.new(0, groundY + 1 + 3, 0),
			Color = accent,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	local signPost = WorldKit.Part({
		Name = `{name}SignPost`,
		Size = Vector3.new(1, 4, 1),
		Position = center + doorOffset + Vector3.new(0, groundY + 1 + wallHeight + 2, 0),
		Color = STONE,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = `{name}Sign`,
		Adornee = signPost,
		Text = label,
		Color = accent,
		Size = UDim2.new(0, 200, 0, 54),
		StudsOffset = Vector3.new(0, 4, 0),
	})
	WorldKit.Light({
		Name = `{name}Light`,
		Parent = signPost,
		Color = accent,
		Brightness = 3,
		Range = 26,
	})
end

local function buildLampPost(folder: Instance, name: string, position: Vector3, groundY: number)
	WorldKit.Pillar({
		Name = name,
		Position = position + Vector3.new(0, groundY, 0),
		Height = 8,
		Thickness = 0.8,
		Color = Color3.fromRGB(40, 40, 52),
		CapColor = Theme.Color.AccentWarning,
		Parent = folder,
	})
end

local function buildStall(folder: Instance, name: string, position: Vector3, groundY: number, accent: Color3)
	WorldKit.Part({
		Name = `{name}Table`,
		Size = Vector3.new(6, 2.5, 3),
		Position = position + Vector3.new(0, groundY + 1.25, 0),
		Color = Color3.fromRGB(60, 44, 32),
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})
	WorldKit.Wedge({
		Name = `{name}Canopy`,
		Size = Vector3.new(7, 2, 4),
		Position = position + Vector3.new(0, groundY + 5, 0),
		Rotation = CFrame.Angles(0, 0, math.rad(180)),
		Color = accent,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = folder,
	})
	for _, sign in { 1, -1 } do
		WorldKit.Part({
			Name = `{name}Post{sign}`,
			Size = Vector3.new(0.5, 4, 0.5),
			Position = position + Vector3.new(2.5 * sign, groundY + 2, -1),
			Color = Color3.fromRGB(60, 44, 32),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = folder,
		})
	end
end

function CommercialZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Commercial")
	local center = zone.Center
	local groundY = WorldLayout.GroundY

	local folder = WorldKit.Group("Commercial", parent)

	WorldKit.TiledFloor({
		Name = "CommercialFloor",
		Width = 130,
		Depth = 140,
		TileSize = 13,
		Thickness = 1,
		Position = center,
		ColorA = STONE,
		ColorB = STONE_LIGHT,
		Parent = folder,
	})

	-- Entrance arch at the west edge (toward the Hub).
	local entranceX = center.X - zone.Size.X / 2 + 4
	for _, sign in { 1, -1 } do
		WorldKit.Pillar({
			Name = `CommercialEntrancePost{sign}`,
			Position = Vector3.new(entranceX, groundY, center.Z + 10 * sign),
			Height = 10,
			Thickness = 1.6,
			Color = STONE,
			CapColor = Theme.Color.AccentPrimary,
			Parent = folder,
		})
	end

	-- Two storefronts flanking the street's north/south sides, both facing
	-- inward toward the central walkable spine.
	buildStorefront(
		folder,
		"StoreFront",
		center + Vector3.new(20, 0, 42),
		groundY,
		Theme.Color.AccentPrimary,
		"STORE",
		Vector3.new(0, 0, -1)
	)
	buildStorefront(
		folder,
		"ShopFront",
		center + Vector3.new(20, 0, -42),
		groundY,
		Theme.Color.Robux,
		"SHOP",
		Vector3.new(0, 0, 1)
	)

	-- Market stalls lining the spine between the two storefronts.
	local stallColors = { Theme.Color.AccentSecondary, Theme.Color.AccentWarning, Theme.Color.AccentInfo }
	for i = 1, 3 do
		buildStall(
			folder,
			`MarketStall{i}`,
			center + Vector3.new(-30 - (i - 1) * 14, 0, (i % 2 == 0) and 12 or -12),
			groundY,
			stallColors[i]
		)
	end

	-- Lamp posts and planters down the spine for density.
	for i = 1, 4 do
		local z = -45 + (i - 1) * 30
		buildLampPost(folder, `CommercialLamp{i}`, center + Vector3.new(-5, 0, z), groundY)
		WorldKit.Part({
			Name = `CommercialPlanter{i}`,
			Size = Vector3.new(3, 1.5, 3),
			Position = center + Vector3.new(-5, groundY + 0.75, z) + Vector3.new(8, 0, 0),
			Color = STONE_LIGHT,
			Material = Enum.Material.Concrete,
			Parent = folder,
		})
	end

	-- Hanging banners between the storefronts, spanning the spine.
	for i = 1, 2 do
		WorldKit.Part({
			Name = `CommercialBanner{i}`,
			Size = Vector3.new(2, 6, 0.2),
			Position = center + Vector3.new(0, groundY + 9, -20 + (i - 1) * 40),
			Color = if i == 1 then Theme.Color.AccentPrimary else Theme.Color.Robux,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = folder,
		})
	end
end

return CommercialZone
