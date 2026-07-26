--!strict
-- CTF Arena: separate from the calm hub, symmetric two-base layout. This is
-- the one zone the CTF/Team services actually depend on at runtime - every
-- team's BaseSpawnName SpawnLocation and FlagStandName Part is named
-- straight from Constants.TEAMS (never hardcoded here) so this can never
-- drift from the naming contract in Constants.lua. CTFService finds these
-- via a recursive descendant search, so nesting them under this zone's
-- Folder is free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldKit = require(script.Parent.WorldKit)

local ArenaZone = {}

local MIDFIELD_Z = 250
local HALF_WIDTH = 50
local HALF_LENGTH = 100 -- floor spans MIDFIELD_Z +/- HALF_LENGTH

local COVER_LAYOUT = {
	{ X = -28, Z = 225, Tall = true },
	{ X = 28, Z = 225, Tall = true },
	{ X = -16, Z = 250, Tall = false },
	{ X = 16, Z = 250, Tall = false },
	{ X = -28, Z = 275, Tall = true },
	{ X = 28, Z = 275, Tall = true },
}

local function buildTeamHalves(zone: Instance)
	for i, team in Constants.TEAMS do
		-- Constants.TEAMS is [Red, Blue] - Red gets the far half (larger Z,
		-- away from the hub), Blue gets the near half.
		local sign = if i == 1 then 1 else -1
		local halfCenterZ = MIDFIELD_Z + sign * (HALF_LENGTH / 2)
		local spawnZ = MIDFIELD_Z + sign * 70
		local flagZ = MIDFIELD_Z + sign * 90
		local backWallZ = MIDFIELD_Z + sign * HALF_LENGTH

		-- Tinted floor wash over this team's half.
		WorldKit.Part({
			Name = `{team.Id}FloorWash`,
			Size = Vector3.new(HALF_WIDTH * 2, 0.1, HALF_LENGTH),
			Position = Vector3.new(0, 0.06, halfCenterZ),
			Color = team.Color,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.65,
			CanCollide = false,
			CastShadow = false,
			Parent = zone,
		})

		-- Back wall banner + a single glowing top-edge cap strip.
		WorldKit.Part({
			Name = `{team.Id}BackWall`,
			Size = Vector3.new(HALF_WIDTH * 2, 10, 1),
			Position = Vector3.new(0, 5, backWallZ),
			Color = team.Color,
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
		WorldKit.Part({
			Name = `{team.Id}BackWallTrim`,
			Size = Vector3.new(HALF_WIDTH * 2, 0.4, 1.4),
			Position = Vector3.new(0, 10.2, backWallZ),
			Color = Theme.Color.TextPrimary,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = zone,
		})

		-- Base spawn. Name is load-bearing - read straight from Constants.
		local spawn = WorldKit.Spawn({
			Name = team.BaseSpawnName,
			Size = Vector3.new(18, 1, 18),
			CFrame = CFrame.new(Vector3.new(0, 0.5, spawnZ), Vector3.new(0, 0.5, MIDFIELD_Z)),
			Color = team.Color,
			TeamColor = BrickColor.new(team.Color),
			Material = Enum.Material.SmoothPlastic,
			Neutral = false,
			Parent = zone,
		})

		-- Flag stand pedestal. Name is load-bearing - CTFService attaches
		-- the flag object at this part's position at runtime; we only need
		-- to build the pedestal it sits on.
		local flagStand = WorldKit.UprightCylinder({
			Name = team.FlagStandName,
			Diameter = 3,
			Height = 2.5,
			Position = Vector3.new(0, 1.25, flagZ),
			Color = team.Color,
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
		WorldKit.UprightCylinder({
			Name = `{team.Id}FlagStandRim`,
			Diameter = 3.6,
			Height = 0.3,
			Position = Vector3.new(0, 2.35, flagZ),
			Color = Theme.Color.AccentPrimary,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = zone,
		})
		local flagLight = Instance.new("PointLight")
		flagLight.Name = "FlagStandLight"
		flagLight.Color = Theme.Color.AccentPrimary
		flagLight.Range = 16
		flagLight.Brightness = 2
		flagLight.Parent = flagStand

		WorldKit.Sign({
			Adornee = spawn,
			Name = `{team.Id}BaseSign`,
			Text = string.upper(team.Name),
			Color = team.Color,
			Size = UDim2.new(0, 220, 0, 50),
			StudsOffset = Vector3.new(0, 6, 0),
		})
	end
end

local function buildWalls(zone: Instance)
	for _, xSign in { 1, -1 } do
		local x = xSign * (HALF_WIDTH + 1)
		local side = if xSign == 1 then "East" else "West"

		WorldKit.Part({
			Name = `ArenaWall{side}`,
			Size = Vector3.new(1, 6, HALF_LENGTH * 2),
			Position = Vector3.new(x, 3, MIDFIELD_Z),
			Color = Theme.Color.Surface,
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
		WorldKit.Part({
			Name = `ArenaWall{side}Trim`,
			Size = Vector3.new(1.4, 0.4, HALF_LENGTH * 2),
			Position = Vector3.new(x, 6.2, MIDFIELD_Z),
			Color = Theme.Color.AccentPrimary,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = zone,
		})
	end

	-- Midfield centerline.
	WorldKit.Part({
		Name = "ArenaMidline",
		Size = Vector3.new(HALF_WIDTH * 2, 0.15, 1.2),
		Position = Vector3.new(0, 0.1, MIDFIELD_Z),
		Color = Theme.Color.TextPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = zone,
	})
end

local function buildMidfieldCover(zone: Instance)
	for i, spec in COVER_LAYOUT do
		if spec.Tall then
			WorldKit.Part({
				Name = `CoverPillar_{i}`,
				Size = Vector3.new(6, 9, 6),
				Position = Vector3.new(spec.X, 4.5, spec.Z),
				Color = Theme.Color.Surface,
				Material = Enum.Material.SmoothPlastic,
				Parent = zone,
			})
			WorldKit.Part({
				Name = `CoverPillarCap_{i}`,
				Size = Vector3.new(6.4, 0.3, 6.4),
				Position = Vector3.new(spec.X, 9.15, spec.Z),
				Color = Theme.Color.AccentPrimary,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
				Parent = zone,
			})
		else
			WorldKit.Part({
				Name = `CoverBlock_{i}`,
				Size = Vector3.new(8, 3, 6),
				Position = Vector3.new(spec.X, 1.5, spec.Z),
				Color = Theme.Color.Stroke,
				Material = Enum.Material.SmoothPlastic,
				Parent = zone,
			})
		end
	end
end

-- Two pylons just outside the hub-facing entrance, capped in each team's
-- color - foreshadows "this is a 2-team arena" before you even step in.
local function buildEntranceGate(zone: Instance)
	local gateZ = MIDFIELD_Z - HALF_LENGTH - 3
	local redColor = Constants.TEAMS[1] and Constants.TEAMS[1].Color or Theme.Team.Red
	local blueColor = Constants.TEAMS[2] and Constants.TEAMS[2].Color or Theme.Team.Blue
	local colors = { redColor, blueColor }

	for i, xSign in { -1, 1 } do
		local x = xSign * 10
		WorldKit.UprightCylinder({
			Name = `GatePylon_{i}`,
			Diameter = 3,
			Height = 12,
			Position = Vector3.new(x, 6, gateZ),
			Color = Theme.Color.Surface,
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
		local cap = WorldKit.UprightCylinder({
			Name = `GatePylonCap_{i}`,
			Diameter = 3.6,
			Height = 1,
			Position = Vector3.new(x, 12.5, gateZ),
			Color = colors[i],
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = zone,
		})
		local light = Instance.new("PointLight")
		light.Name = "GateLight"
		light.Color = colors[i]
		light.Range = 14
		light.Brightness = 2
		light.Parent = cap
	end
end

function ArenaZone.Build(parent: Instance)
	local zone = Instance.new("Folder")
	zone.Name = "Arena"
	zone.Parent = parent

	local floor = WorldKit.Part({
		Name = "ArenaFloor",
		Size = Vector3.new(HALF_WIDTH * 2, 2, HALF_LENGTH * 2),
		Position = Vector3.new(0, -1, MIDFIELD_Z),
		Color = Theme.Color.Background,
		Material = Enum.Material.Slate,
		Parent = zone,
	})

	buildTeamHalves(zone)
	buildWalls(zone)
	buildMidfieldCover(zone)
	buildEntranceGate(zone)

	WorldKit.Sign({
		Adornee = floor,
		Name = "ArenaSign",
		Text = "CTF ARENA",
		Color = Theme.Color.TextPrimary,
		StudsOffset = Vector3.new(0, 22, 0),
	})
end

return ArenaZone
