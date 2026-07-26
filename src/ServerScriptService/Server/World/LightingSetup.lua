--!strict
-- Lighting/atmosphere configuration for the "dark base + neon accents" look
-- (see docs/DESIGN_SYSTEM.md for the full rationale). Kept as its own module
-- instead of inline in MapBuilder so lighting tuning never requires touching
-- geometry code and vice versa.

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

-- Names of effect instances we own, so re-running Apply() (e.g. a script
-- reload in Studio) replaces them cleanly instead of stacking duplicates.
local OWNED_EFFECT_NAMES = {
	"HatchWars_Bloom",
	"HatchWars_ColorCorrection",
	"HatchWars_Atmosphere",
}

local function clearOwnedEffects()
	for _, name in OWNED_EFFECT_NAMES do
		local existing = Lighting:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

function LightingSetup.Apply()
	clearOwnedEffects()

	-- Future tech unlocks accurate Bloom/ColorCorrection/Atmosphere blending
	-- and is what most modern "neon on dark" trend games ship with.
	Lighting.Technology = Enum.Technology.Future

	-- Dusk clock time gives a moody sky without going pitch black, so the
	-- world stays readable while Neon trim still pops against it.
	Lighting.ClockTime = 20
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 1.6
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.Ambient = Color3.fromRGB(24, 24, 36)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 36, 58)
	Lighting.ColorShift_Top = Color3.fromRGB(60, 50, 90)
	Lighting.ColorShift_Bottom = Color3.fromRGB(10, 10, 18)
	Lighting.ShadowSoftness = 0.25
	Lighting.GlobalShadows = true

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HatchWars_Bloom"
	bloom.Intensity = 0.55
	bloom.Threshold = 1.35
	bloom.Size = 20
	bloom.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "HatchWars_ColorCorrection"
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.1
	colorCorrection.Saturation = 0.15
	colorCorrection.TintColor = Color3.fromRGB(248, 250, 255)
	colorCorrection.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "HatchWars_Atmosphere"
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(150, 160, 205)
	atmosphere.Decay = Color3.fromRGB(45, 45, 70)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
end

return LightingSetup
