--!strict
-- Server-side lighting baseline: technology, post effects (bloom, color
-- correction, atmosphere, sun rays, sky) and a bright daytime fallback. The
-- living part - day/night cycle and per-zone color grading - runs on each
-- client in LightingController, driven by the shared LightingConfig. See
-- docs/DESIGN_SYSTEM.md for the full rationale. Kept as its own module
-- instead of inline in MapBuilder so lighting tuning never requires touching
-- geometry code and vice versa.
--
-- Effect instance names below are a contract with LightingController, which
-- finds and tweens them by name.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Shared.LightingConfig)

local LightingSetup = {}

-- Names of effect instances we own, so re-running Apply() (e.g. a script
-- reload in Studio) replaces them cleanly instead of stacking duplicates.
local OWNED_EFFECT_NAMES = {
	"HatchWars_Bloom",
	"HatchWars_ColorCorrection",
	"HatchWars_Atmosphere",
	"HatchWars_SunRays",
	"HatchWars_Sky",
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

	-- Future tech unlocks accurate Bloom/ColorCorrection/Atmosphere blending.
	-- Lighting.Technology is not reliably writable from a game script (it's
	-- primarily a Studio/place-file property), so the authoritative setting
	-- lives in default.project.json (Rojo writes it into the place). This
	-- assignment is a best-effort fallback wrapped in pcall: if the engine
	-- refuses it, every effect below must still be applied - an unguarded
	-- error here previously would have skipped the whole lighting setup.
	local technologyOk = pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	if not technologyOk then
		-- Expected on some engine versions; the project file covers it.
		Lighting:SetAttribute("TechnologySetByScript", false)
	end

	-- Baseline = a bright afternoon. The real time of day is driven per
	-- client by LightingController from the shared, server-time-synced cycle
	-- in LightingConfig; this baseline is what anyone sees for the first
	-- frame, or if that controller ever fails to start - so it must be the
	-- friendly, readable daytime look, not the moody night one.
	local initialState = LightingConfig.StateAt(workspace:GetServerTimeNow())
	Lighting.ClockTime = initialState.ClockTime
	Lighting.GeographicLatitude = 23.5
	Lighting.Brightness = LightingConfig.Day.Brightness
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.Ambient = LightingConfig.Day.Ambient
	Lighting.OutdoorAmbient = LightingConfig.Day.OutdoorAmbient
	Lighting.ColorShift_Top = LightingConfig.Day.ColorShiftTop
	Lighting.ColorShift_Bottom = Color3.fromRGB(30, 26, 40)
	Lighting.ShadowSoftness = 0.3
	Lighting.GlobalShadows = true

	-- Daytime bloom values; LightingController lerps toward the night values
	-- (LightingConfig.Bloom) as the sun sets so Neon trim takes over at night
	-- without white SmoothPlastic surfaces blooming under the bright sun.
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HatchWars_Bloom"
	bloom.Intensity = LightingConfig.Bloom.DayIntensity
	bloom.Threshold = LightingConfig.Bloom.DayThreshold
	bloom.Size = 20
	bloom.Parent = Lighting

	local defaultMood = LightingConfig.DefaultMood
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "HatchWars_ColorCorrection"
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = defaultMood.Contrast
	colorCorrection.Saturation = defaultMood.Saturation
	colorCorrection.TintColor = defaultMood.Tint
	colorCorrection.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "HatchWars_Atmosphere"
	atmosphere.Density = defaultMood.AtmosphereDensity
	atmosphere.Offset = 0.2
	atmosphere.Color = defaultMood.AtmosphereColor
	atmosphere.Decay = Color3.fromRGB(70, 75, 110)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	-- Subtle sun-shaft glow through the haze - cheap and reads as "premium"
	-- at dusk, kept low-intensity so it never washes out gameplay or UI.
	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "HatchWars_SunRays"
	sunRays.Intensity = 0.12
	sunRays.Spread = 0.65
	sunRays.Parent = Lighting

	-- A dedicated Sky instance (rather than leaving Lighting to fall back to
	-- the engine default) so the star count/celestial size are deliberate
	-- choices instead of an accident. No custom skybox/sun/moon texture ids
	-- are set here - inventing an rbxassetid:// would either fail to load or
	-- show something unrelated, so every texture field is left at Roblox's
	-- own built-in default (empty string = "use the default"). At dusk with
	-- Atmosphere haze, a denser starfield reads well once the sky darkens
	-- toward the horizon.
	local sky = Instance.new("Sky")
	sky.Name = "HatchWars_Sky"
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
	sky.SunAngularSize = 11
	sky.MoonAngularSize = 5
	sky.Parent = Lighting
end

return LightingSetup
