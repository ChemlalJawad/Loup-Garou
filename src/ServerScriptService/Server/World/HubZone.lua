--!strict
-- The hub/lobby: the social heart of the map and home to the one
-- SpawnLocation every player actually spawns at (Neutral = true). A layered
-- square plaza (alternating material/color bands read as "designed" instead
-- of one flat slab) wraps a stacked-cylinder fountain centerpiece, all
-- trimmed in neon so the space reads "clean modern trend game" using only
-- Parts. See docs/DESIGN_SYSTEM.md "How the world is laid out" for the
-- zone map this fits into.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldKit = require(script.Parent.WorldKit)

local HubZone = {}

local CENTER = Vector3.new(0, 0, 0)

-- Ground-level convention shared by every zone: each zone's primary platform
-- spans Y -2..0 (top = 0) so it sits flush on MapBuilder's BaseGround plate,
-- whose visible top is at Y = -2. Keeping this consistent across zones is
-- what stops platforms from z-fighting against the ground plate beneath them.
local PLATFORM_TOP = 0

local function buildFountain(zone: Instance)
	local base = CENTER.Y + 0.6 -- top of the inner plaza band

	-- Basin.
	WorldKit.UprightCylinder({
		Name = "FountainBasin",
		Diameter = 16,
		Height = 1.5,
		Position = Vector3.new(0, base + 0.75, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	-- Glowing collar peeking out around the basin's base.
	WorldKit.UprightCylinder({
		Name = "FountainBasinCollar",
		Diameter = 16.6,
		Height = 0.3,
		Position = Vector3.new(0, base + 0.15, 0),
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = zone,
	})
	-- "Water" pool inset in the basin top.
	WorldKit.UprightCylinder({
		Name = "FountainWater",
		Diameter = 13,
		Height = 0.25,
		Position = Vector3.new(0, base + 1.5 + 0.125, 0),
		Color = Theme.Color.AccentInfo,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		Parent = zone,
	})
	-- Center pillar rising from the pool.
	WorldKit.UprightCylinder({
		Name = "FountainPillar",
		Diameter = 3,
		Height = 4.5,
		Position = Vector3.new(0, base + 1.75 + 2.25, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	-- Glowing beacon cap - doubles as a landmark visible from other zones.
	local beacon = WorldKit.Part({
		Name = "FountainBeacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Position = Vector3.new(0, base + 1.75 + 4.5 + 1.5, 0),
		Color = Theme.Color.AccentPrimary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = zone,
	})

	local light = Instance.new("PointLight")
	light.Name = "BeaconLight"
	light.Color = Theme.Color.AccentPrimary
	light.Range = 30
	light.Brightness = 2
	light.Parent = beacon
end

local function buildSpawn(zone: Instance)
	-- The one spawn every player actually lands at first. Placed on the mid
	-- band (outside the fountain's footprint), facing the fountain.
	WorldKit.Spawn({
		Name = "HubSpawn",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(Vector3.new(0, 0.5, 26), Vector3.new(0, 0.5, 0)),
		Color = Theme.Color.SurfaceRaised,
		Material = Enum.Material.SmoothPlastic,
		Neutral = true,
		Parent = zone,
	})
	WorldKit.NeonBorder({
		Name = "HubSpawnTrim",
		Center = Vector3.new(0, 0.31, 26),
		Width = 12,
		Depth = 12,
		Color = Theme.Color.AccentPrimary,
		Parent = zone,
	})
end

function HubZone.Build(parent: Instance)
	local zone = Instance.new("Folder")
	zone.Name = "Hub"
	zone.Parent = parent

	-- Band A: outer plaza slab.
	WorldKit.Part({
		Name = "PlazaOuter",
		Size = Vector3.new(100, 2, 100),
		Position = CENTER + Vector3.new(0, PLATFORM_TOP - 1, 0),
		Color = Theme.Color.Background,
		Material = Enum.Material.Slate,
		Parent = zone,
	})

	-- Band B: mid plaza, raised slightly, ringed in AccentPrimary neon.
	WorldKit.Part({
		Name = "PlazaMid",
		Size = Vector3.new(68, 0.3, 68),
		Position = CENTER + Vector3.new(0, 0.15, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	WorldKit.NeonBorder({
		Name = "PlazaMidTrim",
		Center = CENTER + Vector3.new(0, 0.31, 0),
		Width = 68,
		Depth = 68,
		Color = Theme.Color.AccentPrimary,
		Parent = zone,
	})

	-- Band C: inner plaza (round, for contrast against the square bands),
	-- ringed in a wider glowing "halo" collar, hosts the fountain.
	WorldKit.UprightCylinder({
		Name = "PlazaInner",
		Diameter = 40,
		Height = 0.3,
		Position = CENTER + Vector3.new(0, 0.45, 0),
		Color = Theme.Color.SurfaceRaised,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	WorldKit.UprightCylinder({
		Name = "PlazaInnerHalo",
		Diameter = 41,
		Height = 0.15,
		Position = CENTER + Vector3.new(0, 0.525, 0),
		Color = Theme.Color.AccentSecondary,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = zone,
	})

	buildFountain(zone)
	buildSpawn(zone)
end

return HubZone
