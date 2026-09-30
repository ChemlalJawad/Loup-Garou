--!strict
-- Client-side living lighting:
--   1. Day/night cycle computed locally from workspace:GetServerTimeNow()
--      (see LightingConfig) - every client agrees on the time of day and
--      nothing replicates Lighting properties over the network.
--   2. Per-zone color grading ("moods") blended smoothly as the player walks
--      between zones, so each area feels like a distinct place.
--   3. Decorative lights/emitters (tagged by WorldKit) managed centrally:
--      lamps glow at night and switch off in full daylight, and everything
--      decorative is disabled on low graphics quality.
--
-- Performance: one Heartbeat connection doing a few multiplies. It writes
-- to Lighting every UPDATE_INTERVAL (0.25s) normally, and every frame only
-- while a zone blend is in progress (~1.6s at a time). Decor lights are only
-- touched when the quantized daylight level or quality mode actually changes.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local LightingConfig = require(ReplicatedStorage.Shared.LightingConfig)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local Shell = require(StarterPlayer.StarterPlayerScripts.Client.UI.Shell)

local LightingController = {}

type Mood = LightingConfig.ZoneMood

local localPlayer = Players.LocalPlayer

local bloom: BloomEffect? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local sunRays: SunRaysEffect? = nil

-- Zone mood blending state.
local currentZone: string? = nil
local moodFrom: Mood = LightingConfig.DefaultMood
local moodTo: Mood = LightingConfig.DefaultMood
local blendStartedAt = -math.huge

-- Decor management state.
local lowQuality = false
local lastDecorKey = "" -- quantized daylight + quality, so decor updates only on change
local lastDaylight = 1
local wasNight: boolean? = nil

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpMood(a: Mood, b: Mood, t: number): Mood
	return {
		Tint = a.Tint:Lerp(b.Tint, t),
		Saturation = lerp(a.Saturation, b.Saturation, t),
		Contrast = lerp(a.Contrast, b.Contrast, t),
		AtmosphereColor = a.AtmosphereColor:Lerp(b.AtmosphereColor, t),
		AtmosphereDensity = lerp(a.AtmosphereDensity, b.AtmosphereDensity, t),
	}
end

local function currentBlendedMood(now: number): (Mood, boolean)
	local alpha = math.clamp((now - blendStartedAt) / LightingConfig.ZONE_BLEND_SECONDS, 0, 1)
	-- Ease-out so the change is noticeable on arrival and settles gently.
	local eased = 1 - (1 - alpha) * (1 - alpha)
	return lerpMood(moodFrom, moodTo, eased), alpha < 1
end

-- Graphics quality ------------------------------------------------------------

local function detectLowQuality(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" and level > 0 then
		-- Explicit manual setting: 1-3 is the low end of Roblox's 1-10 slider.
		return level <= 3
	end
	-- "Automatic" (0) gives no numeric level. Treat touch-only devices
	-- (phones/tablets - the bulk of a young audience) as low-power so
	-- decorative particles and extra lights don't eat their frame budget.
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Decorative lights & emitters ------------------------------------------------

local function applyDecorLight(light: Instance, daylight: number)
	if not light:IsA("Light") then
		return
	end
	local base = light:GetAttribute("BaseBrightness")
	local baseBrightness = if type(base) == "number" then base else light.Brightness

	local threshold = LightingConfig.DECOR_LIGHT_ON_BELOW_DAYLIGHT
	if lowQuality or daylight >= threshold then
		light.Enabled = false
		return
	end
	-- Full strength at night, fading toward zero as daylight approaches the
	-- threshold, so lamps "switch on" gradually through dusk.
	local nightFactor = 1 - math.clamp(daylight / threshold, 0, 1)
	light.Enabled = true
	light.Brightness = baseBrightness * (0.35 + 0.65 * nightFactor)
end

-- Emitters may carry a "DecorTime" attribute ("Night" = fireflies, "Day" =
-- pollen) so ambient particles follow the day/night cycle; untagged ones
-- just follow the quality setting.
local function applyDecorEmitter(emitter: Instance, daylight: number)
	if not emitter:IsA("ParticleEmitter") then
		return
	end
	local isNight = daylight < LightingConfig.DECOR_LIGHT_ON_BELOW_DAYLIGHT
	local decorTime = emitter:GetAttribute("DecorTime")
	local timeOk = if decorTime == "Night" then isNight elseif decorTime == "Day" then not isNight else true
	emitter.Enabled = timeOk and not lowQuality
end

local function refreshAllDecor(daylight: number)
	for _, light in CollectionService:GetTagged(LightingConfig.DECOR_LIGHT_TAG) do
		applyDecorLight(light, daylight)
	end
	for _, emitter in CollectionService:GetTagged(LightingConfig.DECOR_EMITTER_TAG) do
		applyDecorEmitter(emitter, daylight)
	end
end

local function maybeRefreshDecor(daylight: number)
	-- Quantize so a slowly-changing daylight value only triggers a sweep over
	-- the tagged instances ~20 times per full dusk, not 4 times a second.
	local key = `{math.floor(daylight * 20)}:{lowQuality}`
	if key == lastDecorKey then
		return
	end
	lastDecorKey = key
	refreshAllDecor(daylight)
end

-- Applying lighting -------------------------------------------------------------

local function applyCycle(state: LightingConfig.DayState)
	local d = state.Daylight
	local day = LightingConfig.Day
	local night = LightingConfig.Night

	Lighting.ClockTime = state.ClockTime
	Lighting.Brightness = lerp(night.Brightness, day.Brightness, d)
	Lighting.Ambient = night.Ambient:Lerp(day.Ambient, d)
	Lighting.OutdoorAmbient = night.OutdoorAmbient:Lerp(day.OutdoorAmbient, d)
	Lighting.ExposureCompensation = lerp(night.ExposureCompensation, day.ExposureCompensation, d)

	local shiftTop = night.ColorShiftTop:Lerp(day.ColorShiftTop, d)
	Lighting.ColorShift_Top = shiftTop:Lerp(LightingConfig.GoldenShiftTop, state.Golden * 0.7)

	if bloom then
		local b = LightingConfig.Bloom
		bloom.Intensity = lerp(b.NightIntensity, b.DayIntensity, d)
		bloom.Threshold = lerp(b.NightThreshold, b.DayThreshold, d)
	end
	if sunRays then
		-- Sun shafts matter most at golden hour, when the sun is low and the
		-- haze catches it; negligible at noon and meaningless at night.
		sunRays.Intensity = 0.06 + 0.2 * state.Golden
		sunRays.Enabled = d > 0.05
	end
end

local function applyMood(mood: Mood, state: LightingConfig.DayState)
	if colorCorrection then
		-- A touch of warmth at sunrise/sunset on top of the zone's own tint.
		local warm = Color3.fromRGB(255, 225, 195)
		colorCorrection.TintColor = mood.Tint:Lerp(warm, state.Golden * 0.35)
		colorCorrection.Saturation = mood.Saturation
		colorCorrection.Contrast = mood.Contrast
	end
	if atmosphere then
		atmosphere.Color = mood.AtmosphereColor
		atmosphere.Density = mood.AtmosphereDensity
	end
end

local function onNightChanged(isNight: boolean)
	if wasNight == nil then
		-- First evaluation after joining: set the baseline, no announcement.
		wasNight = isNight
		return
	end
	if wasNight == isNight then
		return
	end
	wasNight = isNight
	if isNight then
		Shell.Notify("Night falls - Brainrots glow and the Parade has better mutation odds!", "Info")
	else
		Shell.Notify("The sun is up - good morning, Brainrot Hatch Wars!", "Info")
	end
end

local function checkZone(now: number)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local zone = WorldLayout.ZoneAt(root.Position)
	if zone == currentZone then
		return
	end
	-- Start the new blend from wherever the previous blend currently is, so
	-- crossing two zones quickly never snaps.
	local blended = currentBlendedMood(now)
	moodFrom = blended
	moodTo = LightingConfig.MoodFor(zone)
	blendStartedAt = now
	currentZone = zone
end

-- Init -----------------------------------------------------------------------

local function findEffect(name: string, className: string): Instance?
	local effect = Lighting:WaitForChild(name, 15)
	if effect and effect:IsA(className) then
		return effect
	end
	warn(`[LightingController] missing lighting effect "{name}" - that part of the look will be skipped`)
	return nil
end

local function start()
	bloom = findEffect("HatchWars_Bloom", "BloomEffect") :: BloomEffect?
	colorCorrection = findEffect("HatchWars_ColorCorrection", "ColorCorrectionEffect") :: ColorCorrectionEffect?
	atmosphere = findEffect("HatchWars_Atmosphere", "Atmosphere") :: Atmosphere?
	sunRays = findEffect("HatchWars_SunRays", "SunRaysEffect") :: SunRaysEffect?

	lowQuality = detectLowQuality()
	pcall(function()
		local settingsService = UserSettings():GetService("UserGameSettings")
		settingsService:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
			lowQuality = detectLowQuality()
			refreshAllDecor(lastDaylight)
		end)
	end)

	-- Decor instances can appear after Init (zones built late, models created
	-- on this client like Parade walkers); apply the current state on arrival.
	CollectionService:GetInstanceAddedSignal(LightingConfig.DECOR_LIGHT_TAG):Connect(function(light)
		applyDecorLight(light, lastDaylight)
	end)
	CollectionService:GetInstanceAddedSignal(LightingConfig.DECOR_EMITTER_TAG):Connect(function(emitter)
		applyDecorEmitter(emitter, lastDaylight)
	end)

	local sinceCycle = math.huge
	local sinceZone = math.huge
	RunService.Heartbeat:Connect(function(dt)
		sinceCycle += dt
		sinceZone += dt
		local now = os.clock()

		if sinceZone >= LightingConfig.ZONE_CHECK_INTERVAL then
			sinceZone = 0
			checkZone(now)
		end

		local mood, blending = currentBlendedMood(now)
		if sinceCycle < LightingConfig.UPDATE_INTERVAL and not blending then
			return
		end
		sinceCycle = 0

		local state = LightingConfig.StateAt(workspace:GetServerTimeNow())
		lastDaylight = state.Daylight
		applyCycle(state)
		applyMood(mood, state)
		maybeRefreshDecor(state.Daylight)
		onNightChanged(state.IsNight)
	end)
end

function LightingController.Init()
	-- Controllers are started one after another by Main.client.lua, so Init
	-- must never yield: waiting on the server's effect instances happens on
	-- its own thread instead of holding up every controller after this one.
	task.spawn(start)
end

return LightingController
