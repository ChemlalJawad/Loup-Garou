--!strict
-- Egg Hatchery zone: purely atmospheric wayfinding (the real Egg UI opens
-- via the Shell nav bar regardless of where the player is standing) - a
-- cluster of stylized "egg" shapes in ascending rarity order so the space
-- reads "this is where you hatch things" on sight. Rarity colors/order come
-- straight from Theme.Rarity / Constants.RARITY_ORDER so this never drifts
-- from the actual egg system's definition of rarity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldKit = require(script.Parent.WorldKit)

local HatcheryZone = {}

local CENTER = Vector3.new(0, 0, -110)

-- Extra glow/scale treatment for the rarer tiers - the same "more glow =
-- rarer" language Pet Sim X / Adopt Me style games use for their eggs.
local GLOWING_RARITIES = { Legendary = true, Secret = true }

-- Hand-authored shallow arc (bulging toward the hub entrance) rather than a
-- straight row, purely for visual interest.
local X_OFFSETS = { -24, -12, 0, 12, 24 }
local Z_OFFSETS = { 4, 1, -1, 1, 4 }

function HatcheryZone.Build(parent: Instance)
	local zone = Instance.new("Folder")
	zone.Name = "Hatchery"
	zone.Parent = parent

	local platform = WorldKit.Part({
		Name = "HatcheryPlatform",
		Size = Vector3.new(64, 2, 54),
		Position = CENTER + Vector3.new(0, -1, 0),
		Color = Theme.Color.Background,
		Material = Enum.Material.Slate,
		Parent = zone,
	})
	WorldKit.NeonBorder({
		Name = "HatcheryTrim",
		Center = CENTER + Vector3.new(0, 0.2, 0),
		Width = 64,
		Depth = 54,
		Color = Theme.Color.AccentSecondary,
		Parent = zone,
	})

	for i, rarity in Constants.RARITY_ORDER do
		local x = X_OFFSETS[i] or 0
		local z = Z_OFFSETS[i] or 0
		local position = CENTER + Vector3.new(x, 0, z)
		local rarityColor = Theme.RarityColor(rarity)
		local glowing = GLOWING_RARITIES[rarity] == true

		-- Pedestal.
		WorldKit.UprightCylinder({
			Name = `Pedestal_{rarity}`,
			Diameter = 6,
			Height = 2.4,
			Position = position + Vector3.new(0, 1.2, 0),
			Color = Theme.Color.Surface,
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
		-- Glowing rim near the pedestal top, colored per-rarity.
		WorldKit.UprightCylinder({
			Name = `PedestalRim_{rarity}`,
			Diameter = 6.6,
			Height = 0.3,
			Position = position + Vector3.new(0, 2.25, 0),
			Color = rarityColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = zone,
		})

		local eggSize = if glowing then Vector3.new(5.6, 7.8, 5.6) else Vector3.new(5, 7, 5)
		local egg = WorldKit.Part({
			Name = `Egg_{rarity}`,
			Shape = Enum.PartType.Ball,
			Size = eggSize,
			Position = position + Vector3.new(0, 2.4 + eggSize.Y / 2, 0),
			Color = rarityColor,
			Material = if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = zone,
		})

		if glowing then
			local light = Instance.new("PointLight")
			light.Name = "RarityGlow"
			light.Color = rarityColor
			light.Range = if rarity == "Secret" then 22 else 16
			light.Brightness = if rarity == "Secret" then 2.5 else 1.8
			light.Parent = egg
		end
	end

	WorldKit.Sign({
		Adornee = platform,
		Name = "HatcherySign",
		Text = "HATCHERY",
		Color = Theme.Color.AccentSecondary,
		StudsOffset = Vector3.new(0, 18, 0),
	})
end

return HatcheryZone
