--!strict
-- VIP Lounge: an exclusive-feeling interior-ish space that gives the VIP
-- game pass a real place in the world. Purely architectural - this module
-- does NOT gate entry or check pass ownership (that logic lives in
-- ShopService, owned elsewhere, and this file must not couple to it). A
-- grand members-only-looking archway sells the exclusivity visually instead.
--
-- === Coordinate convention =================================================
-- WorldLayout.Get("Lounge") = Center (210, 0, -200), Size (120, 60, 120).
--   minX = 150, maxX = 270, minZ = -260, maxZ = -140.
-- +Z is "north", towards the Commercial District - MapBuilder's
-- PathCommercialLounge lands on our maxZ edge (Z = -140), so that edge stays
-- clear as the entrance. Denser and more intimate than the open plazas is
-- deliberate: the contrast is what sells "exclusive". Every Y is derived
-- arithmetically from the part stacked directly beneath it.
--
-- === Part budget =============================================================
-- Floor ~30 (TiledFloor, TileSize 11 over 100x100), entrance archway ~8,
-- seating pockets (4 x ~6 parts) ~24, raised deck + railing ~14, bar/stage
-- centrepiece ~16, ambient pillars/lighting ~20. Total roughly 120 parts,
-- comfortably under the ~300/zone budget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local LoungeZone = {}
LoungeZone.Order = 16

local DEEP_PURPLE = Color3.fromRGB(24, 18, 34)
local PLUSH = Color3.fromRGB(44, 30, 56)
local GOLD_TRIM = Theme.Color.AccentWarning
local VIP_PURPLE = Theme.Color.AccentSecondary

local function buildSeatCluster(folder: Instance, name: string, center: Vector3, groundY: number)
	WorldKit.Sphere({
		Name = `{name}TableBase`,
		Position = center + Vector3.new(0, groundY + 0.3, 0),
		Diameter = 0.6,
		Color = GOLD_TRIM,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.UprightCylinder({
		Name = `{name}TableTop`,
		Position = center + Vector3.new(0, groundY + 1.6, 0),
		Height = 0.3,
		Diameter = 4,
		Color = Color3.fromRGB(20, 16, 24),
		Material = Enum.Material.Marble,
		Parent = folder,
	})
	local seatAngles = { 0, math.pi / 2, math.pi, 3 * math.pi / 2 }
	for i, angle in seatAngles do
		local seatPos = center + Vector3.new(math.cos(angle) * 4, groundY, math.sin(angle) * 4)
		WorldKit.Part({
			Name = `{name}Seat{i}`,
			Size = Vector3.new(2.4, 1.6, 2.4),
			Position = seatPos + Vector3.new(0, 0.8, 0),
			Color = PLUSH,
			Material = Enum.Material.Fabric,
			Parent = folder,
		})
		WorldKit.Part({
			Name = `{name}SeatBack{i}`,
			Size = Vector3.new(2.4, 2.6, 0.6),
			Position = seatPos - Vector3.new(math.cos(angle), 0, math.sin(angle)) * 0.9 + Vector3.new(0, 1.9, 0),
			Color = PLUSH,
			Material = Enum.Material.Fabric,
			Parent = folder,
		})
	end
end

function LoungeZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Lounge")
	local center = zone.Center
	local groundY = WorldLayout.GroundY

	local folder = WorldKit.Group("Lounge", parent)

	WorldKit.TiledFloor({
		Name = "LoungeFloor",
		Width = 100,
		Depth = 100,
		TileSize = 11,
		Thickness = 1,
		Position = center,
		ColorA = DEEP_PURPLE,
		ColorB = Color3.fromRGB(30, 22, 42),
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "LoungeFloorTrim",
		Width = 100,
		Depth = 100,
		Center = center + Vector3.new(0, 0.55, 0),
		Color = VIP_PURPLE,
		Parent = folder,
	})

	-- Grand entrance archway on the north edge (toward Commercial), with a
	-- rope-line pair of posts suggesting members-only without any actual
	-- access gating.
	local entranceZ = center.Z + zone.Size.Z / 2 - 4
	for _, sign in { 1, -1 } do
		WorldKit.Pillar({
			Name = `LoungeArchPost{sign}`,
			Position = Vector3.new(center.X + 10 * sign, groundY, entranceZ),
			Height = 13,
			Thickness = 2,
			Color = Color3.fromRGB(20, 20, 28),
			CapColor = GOLD_TRIM,
			Parent = folder,
		})
	end
	WorldKit.Part({
		Name = "LoungeArchLintel",
		Size = Vector3.new(24, 2, 2.4),
		Position = Vector3.new(center.X, groundY + 14, entranceZ),
		Color = Color3.fromRGB(20, 20, 28),
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	WorldKit.Part({
		Name = "LoungeArchTrim",
		Size = Vector3.new(24, 0.4, 0.4),
		Position = Vector3.new(center.X, groundY + 13, entranceZ),
		Color = GOLD_TRIM,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	local signPost = WorldKit.Part({
		Name = "LoungeSignPost",
		Size = Vector3.new(1, 5, 1),
		Position = Vector3.new(center.X, groundY + 17, entranceZ),
		Color = Color3.fromRGB(20, 20, 28),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = "LoungeSign",
		Adornee = signPost,
		Text = "VIP LOUNGE",
		Color = GOLD_TRIM,
		Size = UDim2.new(0, 240, 0, 60),
		StudsOffset = Vector3.new(0, 4, 0),
	})
	-- Rope-line posts just inside the arch.
	for _, sign in { 1, -1 } do
		WorldKit.Part({
			Name = `LoungeRopePost{sign}`,
			Size = Vector3.new(0.6, 3, 0.6),
			Position = Vector3.new(center.X + 5 * sign, groundY + 1.5, entranceZ - 4),
			Color = GOLD_TRIM,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = folder,
		})
	end

	-- Centrepiece: a small raised stage with a bar-like counter.
	local stageCenter = center + Vector3.new(0, 0, -20)
	WorldKit.UprightCylinder({
		Name = "LoungeStage",
		Position = stageCenter + Vector3.new(0, groundY + 0.75, 0),
		Height = 1.5,
		Diameter = 20,
		Color = Color3.fromRGB(20, 16, 24),
		Material = Enum.Material.Marble,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "LoungeStageTrim",
		Width = 20,
		Depth = 20,
		Center = stageCenter + Vector3.new(0, groundY + 1.55, 0),
		Color = VIP_PURPLE,
		Parent = folder,
	})
	WorldKit.Part({
		Name = "LoungeBarCounter",
		Size = Vector3.new(12, 3, 2.5),
		Position = stageCenter + Vector3.new(0, groundY + 3, -6),
		Color = Color3.fromRGB(30, 22, 40),
		Material = Enum.Material.Marble,
		Parent = folder,
	})
	WorldKit.Part({
		Name = "LoungeBarTrim",
		Size = Vector3.new(12, 0.3, 2.6),
		Position = stageCenter + Vector3.new(0, groundY + 4.55, -6),
		Color = GOLD_TRIM,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	WorldKit.Light({
		Name = "LoungeStageLight",
		Parent = WorldKit.Part({
			Name = "LoungeStageLightAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = stageCenter + Vector3.new(0, groundY + 8, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		}),
		Color = VIP_PURPLE,
		Brightness = 4,
		Range = 32,
	})

	-- Four seat clusters around the stage.
	local seatClusterAngles = { math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4 }
	for i, angle in seatClusterAngles do
		buildSeatCluster(
			folder,
			`LoungeSeatCluster{i}`,
			stageCenter + Vector3.new(math.cos(angle) * 18, 0, math.sin(angle) * 18),
			groundY
		)
	end

	-- Raised private deck along the south wall, overlooking the stage.
	local deckCenter = center + Vector3.new(0, groundY + 3.5, -42)
	WorldKit.Part({
		Name = "LoungeDeck",
		Size = Vector3.new(70, 1, 12),
		Position = deckCenter,
		Color = PLUSH,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	WorldKit.Stairs({
		Name = "LoungeDeckStairs",
		Steps = 6,
		Width = 6,
		Height = 4,
		Run = 8,
		Axis = "Z",
		Position = deckCenter + Vector3.new(0, -4, 6),
		Color = PLUSH,
		Parent = folder,
	})
	WorldKit.Railing({
		Name = "LoungeDeckRail",
		Axis = "X",
		Position = deckCenter + Vector3.new(0, 0.5, 6),
		Length = 70,
		Color = GOLD_TRIM,
		Parent = folder,
	})

	-- Ambient colonnade ringing the outer floor.
	local pillarRadius = 42
	for i = 1, 8 do
		local angle = (i - 1) / 8 * math.pi * 2
		WorldKit.Pillar({
			Name = `LoungeColonnade{i}`,
			Position = center + Vector3.new(math.cos(angle) * pillarRadius, groundY, math.sin(angle) * pillarRadius),
			Height = 11,
			Thickness = 1.4,
			Color = Color3.fromRGB(22, 18, 30),
			CapColor = VIP_PURPLE,
			Parent = folder,
		})
	end
end

return LoungeZone
