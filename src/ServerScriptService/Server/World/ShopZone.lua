--!strict
-- Shop kiosk: purely atmospheric wayfinding (the real Shop UI opens via the
-- Shell nav bar regardless of location) - a small dark-surface kiosk with a
-- Robux-green glowing belt and canopy underlight so it reads as "the shop"
-- at a glance, reusing the same neon-trim-on-dark-surface language as the
-- rest of the hub.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldKit = require(script.Parent.WorldKit)

local ShopZone = {}

local CENTER = Vector3.new(95, 0, -20)

function ShopZone.Build(parent: Instance)
	local zone = Instance.new("Folder")
	zone.Name = "Shop"
	zone.Parent = parent

	local platform = WorldKit.Part({
		Name = "ShopPlatform",
		Size = Vector3.new(34, 2, 34),
		Position = CENTER + Vector3.new(0, -1, 0),
		Color = Theme.Color.Background,
		Material = Enum.Material.Slate,
		Parent = zone,
	})
	WorldKit.NeonBorder({
		Name = "ShopPlatformTrim",
		Center = CENTER + Vector3.new(0, 0.2, 0),
		Width = 34,
		Depth = 34,
		Color = Theme.Color.Robux,
		Parent = zone,
	})

	-- Kiosk body.
	WorldKit.Part({
		Name = "KioskBody",
		Size = Vector3.new(14, 9, 14),
		Position = CENTER + Vector3.new(0, 4.5, 0),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	-- Glowing "belt" band partway up the body.
	WorldKit.Part({
		Name = "KioskBelt",
		Size = Vector3.new(14.6, 0.6, 14.6),
		Position = CENTER + Vector3.new(0, 5.5, 0),
		Color = Theme.Color.Robux,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = zone,
	})

	-- Canopy roof.
	local canopy = WorldKit.Part({
		Name = "KioskCanopy",
		Size = Vector3.new(17, 1, 17),
		Position = CENTER + Vector3.new(0, 9.5, 0),
		Color = Theme.Color.SurfaceRaised,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	-- Glowing underside rim beneath the canopy overhang, like a lit awning edge.
	WorldKit.NeonBorder({
		Name = "KioskCanopyUnderglow",
		Center = CENTER + Vector3.new(0, 8.8, 0),
		Width = 17,
		Depth = 17,
		Color = Theme.Color.Robux,
		Parent = zone,
	})

	-- Counter ledge facing the hub.
	WorldKit.Part({
		Name = "KioskCounter",
		Size = Vector3.new(6, 3, 2),
		Position = CENTER + Vector3.new(0, 1.5, 7),
		Color = Theme.Color.Surface,
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})

	WorldKit.Sign({
		Adornee = canopy,
		Name = "ShopSign",
		Text = "SHOP",
		Color = Theme.Color.Robux,
		StudsOffset = Vector3.new(0, 8, 0),
	})
end

return ShopZone
