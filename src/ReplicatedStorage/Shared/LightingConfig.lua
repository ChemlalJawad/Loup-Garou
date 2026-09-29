--!strict
-- Day/night cycle + per-zone "mood" grading, shared by server and client.
--
-- The cycle is a pure function of `workspace:GetServerTimeNow()`, which the
-- engine keeps in sync across the server and every client. That means:
--   * every client computes the same time of day with zero network traffic
--     (nothing replicates Lighting.ClockTime every frame), and
--   * server gameplay can ask "is it night?" (the Brainrot Parade boosts
--     mutation odds at night) and get the same answer players see.
--
-- Pacing follows what works in the community's big hangout games: a short
-- cycle (15 min) so a normal session sees at least one sunset, with daytime
-- stretched to ~70% of the cycle because bright, readable daylight is the
-- default a young audience expects - night is the special moment where the
-- neon trim and glowing Brainrots take over.

local LightingConfig = {}

export type DayState = {
	ClockTime: number, -- 0-24, what Lighting.ClockTime should be
	Daylight: number, -- 0 (full night) .. 1 (full day), smoothed around dawn/dusk
	Golden: number, -- 0..1, peaks during sunrise/sunset for warm tinting
	IsNight: boolean,
}

export type ZoneMood = {
	Tint: Color3, -- ColorCorrectionEffect.TintColor
	Saturation: number,
	Contrast: number,
	AtmosphereColor: Color3,
	AtmosphereDensity: number,
}

LightingConfig.CYCLE_SECONDS = 15 * 60
LightingConfig.DAY_FRACTION = 0.7 -- share of the cycle spent between sunrise and sunset
LightingConfig.SUNRISE = 6.5
LightingConfig.SUNSET = 18.5
-- Width (in game hours) of the dawn/dusk blend on either side of sunrise and
-- sunset. Wider = softer transition; 1.5h reads as a proper golden hour.
LightingConfig.TWILIGHT_HOURS = 1.5

-- How often clients re-evaluate the cycle. At a 15-minute cycle the sun moves
-- ~0.1 degrees per 0.25s step - visually continuous, at a quarter of the
-- cost of doing it every frame.
LightingConfig.UPDATE_INTERVAL = 0.25
LightingConfig.ZONE_CHECK_INTERVAL = 0.5
LightingConfig.ZONE_BLEND_SECONDS = 1.6

-- Day and night endpoints for the global Lighting properties. Everything in
-- between is a lerp on `Daylight`.
LightingConfig.Day = {
	Brightness = 2.6,
	Ambient = Color3.fromRGB(120, 118, 135),
	OutdoorAmbient = Color3.fromRGB(150, 150, 170),
	ColorShiftTop = Color3.fromRGB(255, 248, 235),
	ExposureCompensation = 0,
}
LightingConfig.Night = {
	Brightness = 1.1,
	Ambient = Color3.fromRGB(40, 34, 70),
	OutdoorAmbient = Color3.fromRGB(58, 50, 100),
	ColorShiftTop = Color3.fromRGB(90, 70, 160),
	-- Slightly lifted exposure at night: kids on phone screens in bright
	-- rooms need to still see where they are going.
	ExposureCompensation = 0.25,
}
LightingConfig.GoldenShiftTop = Color3.fromRGB(255, 160, 90)

-- Bloom: high threshold by day (only Neon glows, sunlit white plastic
-- doesn't bleed), low threshold + stronger intensity at night, which is when
-- the neon trim and glowing Brainrots become the show.
LightingConfig.Bloom = {
	DayIntensity = 0.35,
	DayThreshold = 1.9,
	NightIntensity = 0.85,
	NightThreshold = 1.1,
}

-- Decorative PointLights (street lamps, landmark glows) are tagged
-- "DecorLight" by WorldKit.Light. They fade in as daylight drops below this
-- level and are disabled outright in full daylight - fewer active lights by
-- day is a free performance win on phones, where most young players are.
LightingConfig.DECOR_LIGHT_ON_BELOW_DAYLIGHT = 0.8
LightingConfig.DECOR_LIGHT_TAG = "DecorLight"
LightingConfig.DECOR_EMITTER_TAG = "DecorEmitter"

-- Neutral mood used outside every zone (open ground, paths).
LightingConfig.DefaultMood = {
	Tint = Color3.fromRGB(255, 255, 255),
	Saturation = 0.18,
	Contrast = 0.08,
	AtmosphereColor = Color3.fromRGB(170, 185, 215),
	AtmosphereDensity = 0.3,
} :: ZoneMood

-- Each zone gets a subtle, distinct grade so walking between areas *feels*
-- like changing place, the way the best hub games signal "you've arrived"
-- without a loading screen. Deliberately subtle - never so strong that a
-- Brainrot's rarity color reads differently from one zone to the next.
local moods: { [string]: ZoneMood } = {
	Hub = {
		Tint = Color3.fromRGB(255, 255, 255),
		Saturation = 0.22,
		Contrast = 0.08,
		AtmosphereColor = Color3.fromRGB(175, 195, 230),
		AtmosphereDensity = 0.28,
	},
	Hatchery = {
		Tint = Color3.fromRGB(255, 240, 255),
		Saturation = 0.3,
		Contrast = 0.1,
		AtmosphereColor = Color3.fromRGB(205, 170, 235),
		AtmosphereDensity = 0.33,
	},
	Commercial = {
		Tint = Color3.fromRGB(255, 248, 232),
		Saturation = 0.2,
		Contrast = 0.08,
		AtmosphereColor = Color3.fromRGB(230, 205, 170),
		AtmosphereDensity = 0.3,
	},
	-- Competitive space: less haze and more contrast so opponents stay
	-- readable at range. Readability beats mood here.
	Arena = {
		Tint = Color3.fromRGB(245, 250, 255),
		Saturation = 0.12,
		Contrast = 0.16,
		AtmosphereColor = Color3.fromRGB(160, 175, 205),
		AtmosphereDensity = 0.18,
	},
	Plaza = {
		Tint = Color3.fromRGB(255, 244, 222),
		Saturation = 0.18,
		Contrast = 0.12,
		AtmosphereColor = Color3.fromRGB(235, 210, 160),
		AtmosphereDensity = 0.3,
	},
	Lounge = {
		Tint = Color3.fromRGB(248, 232, 255),
		Saturation = 0.26,
		Contrast = 0.1,
		AtmosphereColor = Color3.fromRGB(180, 140, 220),
		AtmosphereDensity = 0.36,
	},
	Parade = {
		Tint = Color3.fromRGB(255, 240, 238),
		Saturation = 0.3,
		Contrast = 0.1,
		AtmosphereColor = Color3.fromRGB(235, 175, 185),
		AtmosphereDensity = 0.3,
	},
	-- Candy-bright: the playground should look like the most fun place on
	-- the map from across it.
	FunPark = {
		Tint = Color3.fromRGB(255, 255, 250),
		Saturation = 0.38,
		Contrast = 0.06,
		AtmosphereColor = Color3.fromRGB(180, 225, 240),
		AtmosphereDensity = 0.24,
	},
}
LightingConfig.ZoneMoods = moods

function LightingConfig.MoodFor(zoneId: string?): ZoneMood
	if zoneId and moods[zoneId] then
		return moods[zoneId]
	end
	return LightingConfig.DefaultMood
end

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Cycle phase (0..1) -> ClockTime, with daytime stretched to DAY_FRACTION of
-- the cycle and night compressed into the rest.
function LightingConfig.ClockTimeAt(serverTime: number): number
	local phase = (serverTime % LightingConfig.CYCLE_SECONDS) / LightingConfig.CYCLE_SECONDS
	local dayHours = LightingConfig.SUNSET - LightingConfig.SUNRISE
	local nightHours = 24 - dayHours
	local clock
	if phase < LightingConfig.DAY_FRACTION then
		clock = LightingConfig.SUNRISE + (phase / LightingConfig.DAY_FRACTION) * dayHours
	else
		local nightPhase = (phase - LightingConfig.DAY_FRACTION) / (1 - LightingConfig.DAY_FRACTION)
		clock = LightingConfig.SUNSET + nightPhase * nightHours
	end
	return clock % 24
end

function LightingConfig.StateAt(serverTime: number): DayState
	local clock = LightingConfig.ClockTimeAt(serverTime)
	local twilight = LightingConfig.TWILIGHT_HOURS

	-- Daylight ramps up across [sunrise - tw, sunrise + tw] and down across
	-- [sunset - tw, sunset + tw]; flat 1 in between, flat 0 outside.
	local rising = smoothstep(LightingConfig.SUNRISE - twilight, LightingConfig.SUNRISE + twilight, clock)
	local setting = 1 - smoothstep(LightingConfig.SUNSET - twilight, LightingConfig.SUNSET + twilight, clock)
	local daylight = math.min(rising, setting)

	return {
		ClockTime = clock,
		Daylight = daylight,
		-- 1 - |2d - 1| peaks at 1 exactly mid-transition and is 0 at full day
		-- or full night, which is where a golden-hour tint belongs.
		Golden = 1 - math.abs(2 * daylight - 1),
		IsNight = daylight < 0.35,
	}
end

function LightingConfig.IsNight(serverTime: number): boolean
	return LightingConfig.StateAt(serverTime).IsNight
end

return LightingConfig
