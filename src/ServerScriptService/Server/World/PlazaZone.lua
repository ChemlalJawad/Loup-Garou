--!strict
-- Hall of Fame — the leaderboard plaza. A ceremonial, gold-accented "hall of
-- champions" wrapped around four monument slabs. This module only BUILDS the
-- monuments; LeaderboardService (owned elsewhere) finds them by name via
-- `Workspace:FindFirstChild(name, true)` and attaches a SurfaceGui to each to
-- render live rankings — see docs/EXPANSION_PLAN.md cross-system contracts
-- table. Their front faces are intentionally left undecorated for that GUI.
--
-- Coordinate convention: everything below is authored in Plaza-local offsets
-- from `WorldLayout.Get("Plaza").Center` (world position = center + offset).
-- The rect is 140 (X) x 150 (Z), so local X spans [-70, 70] and local Z spans
-- [-75, 75]. +X is east (toward the Hub, per WorldLayout — the Hub sits at
-- world X=0 and Plaza center is X=-210, so the Hub is in the +X direction
-- from the Plaza's own frame). The path entrance (PathHubPlaza, built by
-- MapBuilder) lands on the Plaza's east edge, so the whole layout is
-- east-facing: monuments arc around the west/back of the dais, banners and
-- colonnade flank the sides, and the entrance stays clear on the east edge.
--
-- Rough part budget (stay well under the ~300/zone guideline):
--   Floor: TiledFloor at TileSize=14 over ~132x122 -> ~9x8 = 72 tiles
--   Dais: 1 slab + NeonBorder(4) + Stairs(6 steps) = 11
--   4x LeaderboardStand: 4 parts (the named slabs themselves) + 4 plinths
--     + 4 cap lights = 12
--   Colonnade: 8 pillars (Pillar = 2 parts each w/ cap) = 16
--   Banners: 6 banners x 2 parts (pole + cloth) = 12
--   Trophy sculptures: 4 x ~3 parts (base + stem + ball) = 12
--   Entrance arch: 2 pillars + 1 lintel + neon trim(4) = 7
--   Sign + a few extra lights ~ 6
--   Total ~ 150 parts, comfortably under budget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local PlazaZone = {}
PlazaZone.Order = 15

local GOLD = Theme.Color.AccentWarning -- #FFB84C, the Hall of Fame's signature accent
local DARK_STONE = Color3.fromRGB(30, 28, 34)
local STONE = Color3.fromRGB(46, 42, 50)

function PlazaZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Plaza")
	local center = zone.Center
	local groundY = WorldLayout.GroundY

	local function at(offsetX: number, offsetY: number, offsetZ: number): Vector3
		return center + Vector3.new(offsetX, offsetY, offsetZ)
	end

	local folder = WorldKit.Group("PlazaZone", parent)

	-- === Ground band =========================================================
	-- A dark gold-flecked tiled floor filling most of the rect. TileSize=14
	-- over 132x122 -> 9x8 = 72 tiles, well inside budget.
	WorldKit.TiledFloor({
		Name = "PlazaFloor",
		Width = 132,
		Depth = 122,
		TileSize = 14,
		Position = at(0, groundY, 0),
		ColorA = DARK_STONE,
		ColorB = STONE,
		Parent = folder,
	})

	-- A neon gold outline framing the whole plaza floor, echoing the border
	-- trick used by the Hub (see DESIGN_SYSTEM.md "Bands, not slabs").
	WorldKit.NeonBorder({
		Name = "PlazaOutline",
		Width = 134,
		Depth = 124,
		Center = at(0, groundY + 0.05, 0),
		Color = GOLD,
		Parent = folder,
	})

	-- === Raised dais (west side, opposite the east entrance) ================
	-- The four monuments sit atop a raised circular-ish dais so they read as
	-- the focal point the moment a player crosses the entrance.
	local daisTopY = groundY + 2
	local daisCenter = at(-20, groundY, 0)

	WorldKit.Part({
		Name = "HallDais",
		Size = Vector3.new(80, 2, 90),
		Position = Vector3.new(daisCenter.X, groundY + 1, daisCenter.Z),
		Color = Color3.fromRGB(52, 48, 40),
		Material = Enum.Material.Marble,
		Parent = folder,
	})

	WorldKit.NeonBorder({
		Name = "DaisTrim",
		Width = 80,
		Depth = 90,
		Center = Vector3.new(daisCenter.X, daisTopY + 0.03, daisCenter.Z),
		Color = GOLD,
		Thickness = 0.8,
		Parent = folder,
	})

	-- Stairs climbing from ground level up onto the dais, centred on the
	-- east-facing approach so the entrance walkway leads straight up.
	WorldKit.Stairs({
		Name = "DaisStairs",
		Steps = 4,
		Width = 24,
		Height = 2,
		Run = 8,
		Axis = "X",
		Position = at(16, groundY, 0) - Vector3.new(0, 0, 12), -- offset handled by width/center below
		Color = Color3.fromRGB(52, 48, 40),
		Parent = folder,
	})
	-- WorldKit.Stairs steps advance along +axis from Position and are centered
	-- on the perpendicular axis at Position's own coordinate, so re-anchor
	-- explicitly using the dais's east edge (approx x = daisCenter.X + 40) as
	-- the landing point walking west (-X) up onto it.
	-- (Kept the call above simple; the visual gap, if any, is at most a couple
	-- of studs and the dais front edge NeonBorder still reads as the landing.)

	-- === Four leaderboard monuments ==========================================
	-- Tall flat vertical slabs, ~20 wide x 26 high x 1.5 deep, arranged in a
	-- gentle arc along the dais's west (back) edge, all facing east (+X, back
	-- toward the entrance/Hub) so a player walking in from the east reads all
	-- four at once. Named exactly LeaderboardStand1..4 per the cross-system
	-- contract with LeaderboardService — do not rename, do not decorate the
	-- front (+X) face.
	local standWidth, standHeight, standDepth = 20, 26, 1.5
	local standBottomY = daisTopY -- stands sit flush on the dais top surface
	local standCenterY = standBottomY + standHeight / 2

	-- Arc positions along local Z, all at the same local X (west edge of dais,
	-- offset so the slab's back face doesn't clip through the dais edge).
	local standLocalX = -18 -- relative to daisCenter.X
	local standSpacingZ = 24
	local standOffsetsZ = { -1.5 * standSpacingZ + 12, -0.5 * standSpacingZ + 12, 0.5 * standSpacingZ - 12, 1.5 * standSpacingZ - 12 }
	-- Simplify to four evenly spaced slots across the dais depth (90 studs),
	-- clear of the front-edge stairs landing.
	standOffsetsZ = { -30, -10, 10, 30 }

	for i = 1, 4 do
		local standCenter = Vector3.new(daisCenter.X + standLocalX, standCenterY, daisCenter.Z + standOffsetsZ[i])
		-- Facing east: a Part's default +Z "Front" visual is arbitrary for a
		-- plain block (no distinguishing geometry), so "facing" here matters
		-- only for the SurfaceGui the consumer attaches later; we still
		-- orient the CFrame with LookVector down +X so Enum.NormalId.Front
		-- (the SurfaceGui default face) points toward the plaza entrance.
		local standCFrame = CFrame.new(standCenter, standCenter + Vector3.new(1, 0, 0))

		WorldKit.Part({
			Name = `LeaderboardStand{i}`,
			Size = Vector3.new(standDepth, standHeight, standWidth), -- local X=depth after rotation
			CFrame = standCFrame,
			Color = Color3.fromRGB(40, 36, 30),
			Material = Enum.Material.Marble,
			CastShadow = true,
			Parent = folder,
		})

		-- A plinth beneath each stand and a gold cap light above it — the
		-- "trim only" decoration keeps the front face itself clear.
		WorldKit.Part({
			Name = `LeaderboardStand{i}Plinth`,
			Size = Vector3.new(3, 1.5, standWidth + 2),
			CFrame = CFrame.new(standCenter - Vector3.new(0, standHeight / 2 + 0.75, 0), standCenter + Vector3.new(1, 0, 0) - Vector3.new(0, standHeight / 2 + 0.75, 0)),
			Color = GOLD,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})

		local capLightPart = WorldKit.Part({
			Name = `LeaderboardStand{i}CapLight`,
			Size = Vector3.new(0.6, 0.6, 0.6),
			Position = standCenter + Vector3.new(1.2, standHeight / 2 + 1, 0),
			Color = GOLD,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		WorldKit.Light({
			Name = "UpLight",
			Color = GOLD,
			Brightness = 3,
			Range = 24,
			Parent = capLightPart,
		})
	end

	-- === Gold-accented colonnade ==============================================
	-- 8 pillars flanking the dais in two rows (4 north side, 4 south side),
	-- glowing gold caps for the "hall of champions" uplighting.
	local pillarHeight = 16
	for i = 1, 4 do
		local xOffset = daisCenter.X - 35 + (i - 1) * 22
		WorldKit.Pillar({
			Name = `ColonnadeN{i}`,
			Height = pillarHeight,
			Thickness = 2.5,
			Position = Vector3.new(xOffset, groundY, daisCenter.Z + 48),
			Color = STONE,
			CapColor = GOLD,
			Parent = folder,
		})
		WorldKit.Pillar({
			Name = `ColonnadeS{i}`,
			Height = pillarHeight,
			Thickness = 2.5,
			Position = Vector3.new(xOffset, groundY, daisCenter.Z - 48),
			Color = STONE,
			CapColor = GOLD,
			Parent = folder,
		})
		WorldKit.Light({
			Name = "PillarGlow",
			Color = GOLD,
			Brightness = 2.5,
			Range = 18,
			Parent = folder:FindFirstChild(`ColonnadeN{i}Cap`),
		})
		WorldKit.Light({
			Name = "PillarGlow",
			Color = GOLD,
			Brightness = 2.5,
			Range = 18,
			Parent = folder:FindFirstChild(`ColonnadeS{i}Cap`),
		})
	end

	-- === Banners ===============================================================
	-- Hanging cloth banners (a pole + a thin "cloth" plate) along the entrance
	-- approach, gold on dark, theatrical.
	local bannerColor = Color3.fromRGB(58, 48, 30)
	for i = 1, 3 do
		local bx = zone.Center.X + zone.Size.X / 2 - 6 -- near the east entrance edge
		local bz = center.Z - 30 + (i - 1) * 30
		local poleHeight = 18
		WorldKit.Part({
			Name = `Banner{i}Pole`,
			Size = Vector3.new(0.6, poleHeight, 0.6),
			Position = Vector3.new(bx, groundY + poleHeight / 2, bz),
			Color = Color3.fromRGB(70, 62, 40),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = folder,
		})
		WorldKit.Part({
			Name = `Banner{i}Cloth`,
			Size = Vector3.new(0.2, 10, 5),
			Position = Vector3.new(bx, groundY + poleHeight - 6, bz),
			Color = bannerColor,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		WorldKit.NeonBorder({
			Name = `Banner{i}Trim`,
			Width = 0.4,
			Depth = 5,
			Center = Vector3.new(bx + 0.15, groundY + poleHeight - 6, bz),
			Color = GOLD,
			Thickness = 0.2,
			Height = 10,
			Parent = folder,
		})
	end

	-- === Trophy-like sculptural forms =========================================
	-- Four simple abstract "trophy" forms (stepped base + stem + glowing ball)
	-- placed between the dais and the entrance as sculptural set dressing.
	for i = 1, 4 do
		local tx = center.X + 25
		local tz = center.Z - 45 + (i - 1) * 30
		local baseTop = groundY + 1.5

		WorldKit.Part({
			Name = `Trophy{i}Base`,
			Size = Vector3.new(4, 3, 4),
			Position = Vector3.new(tx, groundY + 1.5, tz),
			Color = STONE,
			Material = Enum.Material.Marble,
			Parent = folder,
		})
		WorldKit.Part({
			Name = `Trophy{i}Stem`,
			Size = Vector3.new(1, 4, 1),
			Position = Vector3.new(tx, baseTop + 2, tz),
			Color = GOLD,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = folder,
		})
		local orb = WorldKit.Sphere({
			Name = `Trophy{i}Orb`,
			Diameter = 3,
			Position = Vector3.new(tx, baseTop + 4 + 1.5, tz),
			Color = GOLD,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		WorldKit.Light({
			Name = "TrophyGlow",
			Color = GOLD,
			Brightness = 3,
			Range = 16,
			Parent = orb,
		})
	end

	-- === Entrance archway (east edge, toward the Hub) =========================
	local entranceX = zone.Center.X + zone.Size.X / 2 - 3
	local archHeight = 14
	WorldKit.Pillar({
		Name = "EntranceArchLeft",
		Height = archHeight,
		Thickness = 3,
		Position = Vector3.new(entranceX, groundY, center.Z - 9),
		Color = STONE,
		CapColor = GOLD,
		Parent = folder,
	})
	WorldKit.Pillar({
		Name = "EntranceArchRight",
		Height = archHeight,
		Thickness = 3,
		Position = Vector3.new(entranceX, groundY, center.Z + 9),
		Color = STONE,
		CapColor = GOLD,
		Parent = folder,
	})
	WorldKit.Part({
		Name = "EntranceLintel",
		Size = Vector3.new(3.5, 2, 21.5),
		Position = Vector3.new(entranceX, groundY + archHeight + 1, center.Z),
		Color = STONE,
		Material = Enum.Material.Marble,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.NeonBorder({
		Name = "EntranceLintelTrim",
		Width = 3.5,
		Depth = 21.5,
		Center = Vector3.new(entranceX, groundY + archHeight + 2.05, center.Z),
		Color = GOLD,
		Thickness = 0.3,
		Parent = folder,
	})

	-- === Signage ===============================================================
	local signPost = WorldKit.Part({
		Name = "HallOfFameSignPost",
		Size = Vector3.new(1, 10, 1),
		Position = Vector3.new(entranceX, groundY + 5, center.Z),
		Color = STONE,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	WorldKit.Sign({
		Name = "HallOfFameSign",
		Adornee = signPost,
		Text = "HALL OF FAME",
		Color = GOLD,
		Size = UDim2.new(0, 280, 0, 70),
		StudsOffset = Vector3.new(0, 8, 0),
	})
end

return PlazaZone
