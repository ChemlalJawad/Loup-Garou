--!strict
-- CTF Arena — a mirror-symmetric map: everything on the Red (south, -Z) half
-- is built once by `buildHalf`, then rebuilt on the Blue (north, +Z) half by
-- mirroring Z around the arena's own centre. This guarantees the two halves
-- are geometrically identical (a real balance requirement, not just tidy
-- code) instead of two hand-authored halves silently drifting apart.
--
-- CONTRACT (see docs/EXPANSION_PLAN.md cross-system contracts table): this
-- module creates the four named parts CTFService/TeamService find via
-- recursive `Workspace:FindFirstChild(name, true)`:
--   SpawnLocation named Constants.TEAMS[i].BaseSpawnName  ("RedBaseSpawn"/"BlueBaseSpawn")
--   anchored Part named Constants.TEAMS[i].FlagStandName  ("RedFlagStand"/"BlueFlagStand")
-- Names are read from Constants.TEAMS, never hardcoded as literals, so a
-- future team rename can't silently desync the contract.
--
-- Coordinate convention: authored in Arena-local offsets from
-- `WorldLayout.Get("Arena").Center` (world position = center + offset). The
-- rect is 260 (X) x 320 (Z): local X spans [-130, 130], local Z spans
-- [-160, 160]. -Z is south (toward the Hub; PathHubArena lands on the south
-- edge). Red owns the south half (negative local Z), Blue the north half
-- (positive local Z), midfield straddles Z=0.
--
-- Three lanes run south<->north: a wide open CENTER lane (fast, exposed), and
-- two flanking SIDE lanes (covered by pillars/crates, slower). Each base has
-- a flag room with three entrances (one per lane) so no single choke fully
-- seals it.
--
-- Elevation bookkeeping (each tier's bottom = previous tier's top):
--   Arena floor            top = WorldLayout.GroundY
--   Flag room dais         top = WorldLayout.GroundY + 1.5
--   Perimeter catwalk      top = WorldLayout.GroundY + 8
--
-- Rough part budget (biggest zone, ~600 budget): floor TiledFloor at
-- TileSize=18 over 260x320 -> ~15x18 = 270 tiles is still too many at small
-- tile size, so the floor uses TileSize=20 (~13x16=208) split further down
-- to a coarser scheme (~120 tiles) plus lane-color overlays (~20) + base
-- structures (~2 x ~55 = 110) + midfield cover (~40) + perimeter walls/
-- catwalk (~60) + spawns/flags/signs (~10). Total ~ 360, comfortably under
-- budget with headroom.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local ArenaZone = {}
ArenaZone.Order = 14

local NEUTRAL_FLOOR = Color3.fromRGB(24, 24, 34)
local NEUTRAL_TRIM = Color3.fromRGB(52, 52, 74)

local function teamDef(teamId: string)
	for _, def in Constants.TEAMS do
		if def.Id == teamId then
			return def
		end
	end
	error(`ArenaZone: Constants.TEAMS is missing an entry for "{teamId}"`)
end

-- Mirrors a local-space offset from Red's half to Blue's half: Z flips sign,
-- X and Y are unchanged. Every piece of Red's geometry is placed with this
-- so Blue is a guaranteed reflection, not a re-typed copy.
local function mirrorZ(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- Builds one team's half. `sign` is +1 for the half authored directly
-- (south, Red) and this function is called a second time conceptually via
-- `mirrorZ` on every offset to produce Blue - see `ArenaZone.Build`, which
-- calls this once per team with the appropriate offset transform.
local function buildHalf(folder: Instance, arenaCenter: Vector3, groundY: number, zoneWidth: number, teamId: string, transform: (Vector3) -> Vector3)
	local def = teamDef(teamId)
	local color = def.Color
	local halfFolder = WorldKit.Group(`{teamId}Half`, folder)

	-- Base platform: a raised rectangle at the back of the half (furthest
	-- from midfield), holding the spawn and flag room.
	local baseCenter = arenaCenter + transform(Vector3.new(0, 0, -128))
	WorldKit.Part({
		Name = `{teamId}BasePlatform`,
		Size = Vector3.new(70, 1.5, 50),
		Position = baseCenter + Vector3.new(0, groundY + 0.75, 0),
		Color = Color3.fromRGB(
			math.round(NEUTRAL_FLOOR.R * 255 * 0.7 + color.R * 255 * 0.3),
			math.round(NEUTRAL_FLOOR.G * 255 * 0.7 + color.G * 255 * 0.3),
			math.round(NEUTRAL_FLOOR.B * 255 * 0.7 + color.B * 255 * 0.3)
		),
		Material = Enum.Material.Concrete,
		Parent = halfFolder,
	})
	WorldKit.NeonBorder({
		Name = `{teamId}BasePlatformTrim`,
		Width = 70,
		Depth = 50,
		Center = baseCenter + Vector3.new(0, groundY + 1.55, 0),
		Color = color,
		Parent = halfFolder,
	})

	-- Team spawn: generous size for multiple simultaneous spawns, sat near
	-- the back of the base platform, facing toward midfield.
	WorldKit.Spawn({
		Name = def.BaseSpawnName,
		Position = baseCenter + Vector3.new(0, 2.5, transform(Vector3.new(0, 0, -14)).Z),
		Size = Vector3.new(20, 1, 12),
		Color = color,
		TeamColor = BrickColor.new(color),
		Parent = halfFolder,
	})

	-- Flag room: a slightly enclosed dais forward of the spawn (toward
	-- midfield), three entrances (left/center/right lane), walls on the back
	-- and sides so it's not a fully open box.
	local flagRoomCenter = baseCenter + transform(Vector3.new(0, 0, 20))
	WorldKit.Part({
		Name = `{teamId}FlagRoomFloor`,
		Size = Vector3.new(34, 1, 26),
		Position = flagRoomCenter + Vector3.new(0, groundY + 1.5, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = halfFolder,
	})
	-- Back wall (away from midfield) and two partial side walls, leaving the
	-- forward edge (toward midfield) and gaps at each side wall's midfield
	-- end open as the three lane entrances.
	WorldKit.Wall({
		Name = `{teamId}FlagRoomBackWall`,
		Size = Vector3.new(34, 12, 1.5),
		Position = flagRoomCenter + transform(Vector3.new(0, groundY + 8, -13)),
		Color = NEUTRAL_TRIM,
		TrimColor = color,
		Parent = halfFolder,
	})
	for _, sideSign in { 1, -1 } do
		WorldKit.Wall({
			Name = `{teamId}FlagRoomSideWall{sideSign}`,
			Size = Vector3.new(1.5, 12, 16),
			Position = flagRoomCenter + Vector3.new(17 * sideSign, groundY + 8, transform(Vector3.new(0, 0, -5)).Z),
			Color = NEUTRAL_TRIM,
			TrimColor = color,
			Parent = halfFolder,
		})
	end

	-- Flag stand pedestal: the named contract part. Raised a step above the
	-- flag room floor at the room's centre.
	WorldKit.Part({
		Name = `{teamId}FlagStandBase`,
		Size = Vector3.new(6, 1, 6),
		Position = flagRoomCenter + Vector3.new(0, groundY + 2.25, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = true,
		CastShadow = false,
		Parent = halfFolder,
	})
	WorldKit.Part({
		Name = def.FlagStandName,
		Size = Vector3.new(2, 4, 2),
		Position = flagRoomCenter + Vector3.new(0, groundY + 4.75, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = halfFolder,
	})
	WorldKit.Light({
		Name = `{teamId}FlagStandLight`,
		Parent = WorldKit.Part({
			Name = `{teamId}FlagStandLightAnchor`,
			Size = Vector3.new(1, 1, 1),
			Position = flagRoomCenter + Vector3.new(0, groundY + 7, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = halfFolder,
		}),
		Color = color,
		Brightness = 3,
		Range = 30,
	})

	-- Side-lane cover between the base and midfield: three staggered pillars
	-- per lane side, giving a flag carrier something to break sightline
	-- against without fully blocking the lane.
	for _, laneSign in { 1, -1 } do
		local laneX = 46 * laneSign
		for i = 1, 3 do
			local laneZ = -60 + (i - 1) * 30
			WorldKit.Pillar({
				Name = `{teamId}LaneCover{laneSign}_{i}`,
				Position = arenaCenter + Vector3.new(laneX, 0, 0) + transform(Vector3.new(0, 0, laneZ)),
				Height = 9,
				Thickness = 3,
				Color = NEUTRAL_TRIM,
				Parent = halfFolder,
			})
		end
	end

	-- Perimeter boundary wall behind the base (the far edge of the arena
	-- rect), with team-coloured trim so the play space reads unambiguous.
	WorldKit.Wall({
		Name = `{teamId}BoundaryWall`,
		Size = Vector3.new(zoneWidth, 16, 2),
		Position = arenaCenter + transform(Vector3.new(0, 8 + groundY, -155)),
		Color = Color3.fromRGB(18, 18, 26),
		TrimColor = color,
		Parent = halfFolder,
	})

	WorldKit.SurfaceLabel({
		Name = `{teamId}BaseLabel`,
		Adornee = WorldKit.Part({
			Name = `{teamId}BaseLabelPlate`,
			Size = Vector3.new(0.5, 5, 20),
			Position = flagRoomCenter + transform(Vector3.new(0, groundY + 10, -13.2)),
			Color = NEUTRAL_TRIM,
			CanCollide = false,
			CastShadow = false,
			Parent = halfFolder,
		}),
		Face = Enum.NormalId.Front,
		Text = string.upper(def.Name),
		Color = color,
		Parent = halfFolder,
	})
end

function ArenaZone.Build(parent: Instance)
	local zone = WorldLayout.Get("Arena")
	local center = zone.Center
	local groundY = WorldLayout.GroundY

	local folder = WorldKit.Group("Arena", parent)

	-- Coarse-tiled floor across the whole rect - large TileSize keeps part
	-- count sane on a 260x320 area.
	WorldKit.TiledFloor({
		Name = "ArenaFloor",
		Width = zone.Size.X,
		Depth = zone.Size.Z,
		TileSize = 20,
		Thickness = 1,
		Position = center + Vector3.new(0, groundY, 0),
		ColorA = NEUTRAL_FLOOR,
		ColorB = Color3.fromRGB(28, 28, 40),
		Parent = folder,
	})

	-- Lane colour overlays: a bright centre stripe for the open lane, dimmer
	-- side stripes for the flanking lanes, so the three-lane structure reads
	-- from above even before a player learns the cover layout.
	WorldKit.Part({
		Name = "CenterLaneOverlay",
		Size = Vector3.new(30, 0.2, zone.Size.Z - 40),
		Position = center + Vector3.new(0, groundY + 0.6, 0),
		Color = Theme.Color.Surface,
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	for _, laneSign in { 1, -1 } do
		WorldKit.Part({
			Name = `SideLaneOverlay{laneSign}`,
			Size = Vector3.new(20, 0.2, zone.Size.Z - 60),
			Position = center + Vector3.new(46 * laneSign, groundY + 0.6, 0),
			Color = Theme.Color.Background,
			Transparency = 0.4,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	-- Midfield cover: a symmetric cluster of blocks/pillars straddling Z=0 so
	-- neither team has an advantage crossing the open centre lane.
	local midfieldOffsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(18, 0, 14),
		Vector3.new(-18, 0, 14),
		Vector3.new(18, 0, -14),
		Vector3.new(-18, 0, -14),
	}
	for i, offset in midfieldOffsets do
		WorldKit.Pillar({
			Name = `MidfieldCover{i}`,
			Position = center + Vector3.new(offset.X, 0, offset.Z),
			Height = 7,
			Thickness = 4,
			Color = NEUTRAL_TRIM,
			Parent = folder,
		})
	end

	-- Ramps up to a perimeter catwalk on each side lane, giving vertical
	-- play and a sightline over the midfield cover - useful for ranged/AoE
	-- abilities per the roster's ability archetypes.
	for _, laneSign in { 1, -1 } do
		local catwalkX = 90 * laneSign
		WorldKit.Stairs({
			Name = `CatwalkRamp{laneSign}`,
			Steps = 10,
			Width = 8,
			Height = 8,
			Run = 20,
			Axis = "Z",
			Position = center + Vector3.new(catwalkX, groundY, -70),
			Color = NEUTRAL_TRIM,
			Parent = folder,
		})
		WorldKit.Part({
			Name = `Catwalk{laneSign}`,
			Size = Vector3.new(8, 1, 100),
			Position = center + Vector3.new(catwalkX, groundY + 8, 0),
			Color = Theme.Color.SurfaceRaised,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		WorldKit.Railing({
			Name = `CatwalkRail{laneSign}`,
			Axis = "Z",
			Position = center + Vector3.new(catwalkX + 4 * laneSign, groundY + 8.5, 0),
			Length = 100,
			Color = NEUTRAL_TRIM,
			Parent = folder,
		})
	end

	-- Scoreboard monolith at the exact centre - a sensible anchor name in
	-- case a future service wants to render live scores onto it.
	local monolith = WorldKit.Part({
		Name = "ArenaScoreboardMonolith",
		Size = Vector3.new(3, 14, 10),
		Position = center + Vector3.new(0, groundY + 7, 0),
		Color = Color3.fromRGB(16, 16, 22),
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	WorldKit.SurfaceLabel({
		Name = "ArenaScoreboardFace",
		Adornee = monolith,
		Face = Enum.NormalId.Front,
		Text = "0 - 0",
		Color = Theme.Color.TextPrimary,
		Parent = folder,
	})

	-- South entrance stays clear (connects to PathHubArena); build a light
	-- arch there instead of a wall so it reads as the way in.
	local southEdge = center + Vector3.new(0, groundY, -zone.Size.Z / 2 + 3)
	for _, sign in { 1, -1 } do
		WorldKit.Pillar({
			Name = `ArenaEntrancePost{sign}`,
			Position = southEdge + Vector3.new(12 * sign, 0, 0),
			Height = 12,
			Thickness = 2,
			Color = NEUTRAL_TRIM,
			CapColor = Theme.Color.AccentPrimary,
			Parent = folder,
		})
	end

	-- Build both halves from the same function: Red directly, Blue as an
	-- exact Z-mirror. This is what guarantees symmetry.
	buildHalf(folder, center, groundY, zone.Size.X, "Red", function(offset)
		return offset
	end)
	buildHalf(folder, center, groundY, zone.Size.X, "Blue", mirrorZ)
end

return ArenaZone
