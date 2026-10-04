--!strict
-- What the sky and the light look like at every hour: a handful of
-- keyframes (deep night, dawn, morning, noon, golden hour, sunset, dusk)
-- blended by the clock. Pure data + maths; SkyController applies it.

local Sky = {}

export type Look = {
	Night: number, -- 0 day .. 1 full night
	Brightness: number,
	Exposure: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ShiftTop: Color3,
	Density: number,
	Haze: number,
	Glare: number,
	AirColor: Color3,
	AirDecay: Color3,
	Tint: Color3,
	Saturation: number,
	Contrast: number,
	Bloom: number,
	SunRays: number,
	CloudColor: Color3,
	CloudCover: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local KEYS: { { Hour: number, Look: Look } } = {
	{ Hour = 0, Look = { Night = 1, Brightness = 0.5, Exposure = -0.7, Ambient = rgb(8, 10, 22), OutdoorAmbient = rgb(28, 34, 62), ShiftTop = rgb(40, 50, 90), Density = 0.4, Haze = 0.6, Glare = 0, AirColor = rgb(36, 44, 76), AirDecay = rgb(16, 20, 40), Tint = rgb(170, 186, 255), Saturation = -0.2, Contrast = 0.12, Bloom = 0.9, SunRays = 0, CloudColor = rgb(52, 58, 82), CloudCover = 0.62 } },
	{ Hour = 4.8, Look = { Night = 1, Brightness = 0.5, Exposure = -0.65, Ambient = rgb(10, 12, 26), OutdoorAmbient = rgb(32, 38, 66), ShiftTop = rgb(44, 54, 94), Density = 0.4, Haze = 0.8, Glare = 0, AirColor = rgb(40, 48, 82), AirDecay = rgb(20, 24, 46), Tint = rgb(176, 190, 255), Saturation = -0.18, Contrast = 0.12, Bloom = 0.9, SunRays = 0, CloudColor = rgb(60, 66, 92), CloudCover = 0.6 } },
	{ Hour = 6.2, Look = { Night = 0.35, Brightness = 1.6, Exposure = -0.15, Ambient = rgb(60, 46, 50), OutdoorAmbient = rgb(150, 110, 100), ShiftTop = rgb(255, 160, 110), Density = 0.42, Haze = 2.2, Glare = 0.8, AirColor = rgb(240, 170, 130), AirDecay = rgb(170, 90, 90), Tint = rgb(255, 228, 210), Saturation = 0.1, Contrast = 0.06, Bloom = 0.7, SunRays = 0.14, CloudColor = rgb(255, 190, 170), CloudCover = 0.55 } },
	{ Hour = 8.5, Look = { Night = 0, Brightness = 2.6, Exposure = 0, Ambient = rgb(70, 66, 64), OutdoorAmbient = rgb(140, 130, 120), ShiftTop = rgb(255, 236, 210), Density = 0.3, Haze = 1.2, Glare = 0.3, AirColor = rgb(200, 205, 215), AirDecay = rgb(120, 130, 150), Tint = rgb(255, 250, 244), Saturation = 0.08, Contrast = 0.05, Bloom = 0.45, SunRays = 0.06, CloudColor = rgb(255, 252, 248), CloudCover = 0.5 } },
	{ Hour = 13, Look = { Night = 0, Brightness = 3, Exposure = 0.05, Ambient = rgb(76, 74, 72), OutdoorAmbient = rgb(150, 142, 134), ShiftTop = rgb(255, 248, 236), Density = 0.26, Haze = 1, Glare = 0.2, AirColor = rgb(205, 214, 228), AirDecay = rgb(120, 140, 170), Tint = rgb(255, 252, 248), Saturation = 0.1, Contrast = 0.05, Bloom = 0.4, SunRays = 0.05, CloudColor = rgb(255, 255, 255), CloudCover = 0.48 } },
	{ Hour = 16.6, Look = { Night = 0, Brightness = 3, Exposure = 0.05, Ambient = rgb(80, 70, 60), OutdoorAmbient = rgb(150, 132, 110), ShiftTop = rgb(255, 222, 176), Density = 0.3, Haze = 1.4, Glare = 0.4, AirColor = rgb(204, 192, 168), AirDecay = rgb(122, 107, 92), Tint = rgb(255, 247, 235), Saturation = 0.08, Contrast = 0.06, Bloom = 0.5, SunRays = 0.07, CloudColor = rgb(255, 244, 226), CloudCover = 0.5 } },
	{ Hour = 18.4, Look = { Night = 0.2, Brightness = 2, Exposure = -0.05, Ambient = rgb(70, 44, 44), OutdoorAmbient = rgb(150, 96, 84), ShiftTop = rgb(255, 130, 80), Density = 0.4, Haze = 2.4, Glare = 1, AirColor = rgb(240, 140, 100), AirDecay = rgb(150, 70, 80), Tint = rgb(255, 214, 196), Saturation = 0.14, Contrast = 0.08, Bloom = 0.7, SunRays = 0.16, CloudColor = rgb(255, 160, 140), CloudCover = 0.55 } },
	{ Hour = 19.6, Look = { Night = 0.75, Brightness = 0.9, Exposure = -0.45, Ambient = rgb(24, 20, 40), OutdoorAmbient = rgb(60, 52, 90), ShiftTop = rgb(110, 80, 140), Density = 0.42, Haze = 1.4, Glare = 0.2, AirColor = rgb(80, 64, 110), AirDecay = rgb(40, 30, 64), Tint = rgb(196, 190, 255), Saturation = -0.1, Contrast = 0.1, Bloom = 0.85, SunRays = 0.04, CloudColor = rgb(96, 80, 120), CloudCover = 0.58 } },
	{ Hour = 21, Look = { Night = 1, Brightness = 0.5, Exposure = -0.7, Ambient = rgb(8, 10, 22), OutdoorAmbient = rgb(28, 34, 62), ShiftTop = rgb(40, 50, 90), Density = 0.4, Haze = 0.6, Glare = 0, AirColor = rgb(36, 44, 76), AirDecay = rgb(16, 20, 40), Tint = rgb(170, 186, 255), Saturation = -0.2, Contrast = 0.12, Bloom = 0.9, SunRays = 0, CloudColor = rgb(52, 58, 82), CloudCover = 0.62 } },
}

local function mix(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b :: Color3, t)
	end
	return a + (b - a) * t
end

-- The look at `clock` (hours, 0-24), blended between its two keyframes.
function Sky.At(clock: number): Look
	clock %= 24
	local count = #KEYS
	for i = 1, count do
		local a = KEYS[i]
		local b = KEYS[i % count + 1]
		local from, to = a.Hour, if i == count then b.Hour + 24 else b.Hour
		if clock >= from and clock < to then
			local t = (clock - from) / (to - from)
			t = t * t * (3 - 2 * t) -- smoothstep
			local out: any = {}
			for key, value in a.Look :: any do
				out[key] = mix(value, (b.Look :: any)[key], t)
			end
			return out :: Look
		end
	end
	return KEYS[1].Look
end

-- Weather on top of the hour's look: `kind` "Rain" or "Fog", faded in by
-- `amount` (0 clear .. 1 full). Rain greys and dims the day and covers the
-- sky; fog thickens the air into a pale haze. Soft either way: never a
-- storm. At night the change is mostly the cloud and the air.
local function weatherTarget(look: Look, kind: string): Look
	local out = table.clone(look :: any)
	local day = 1 - look.Night
	if kind == "Rain" then
		out.Brightness = look.Brightness * (1 - 0.35 * day)
		out.Exposure = look.Exposure - 0.12 * day
		out.OutdoorAmbient = look.OutdoorAmbient:Lerp(rgb(120, 126, 136), 0.5 * day)
		out.ShiftTop = look.ShiftTop:Lerp(rgb(150, 156, 168), 0.6 * day)
		out.Density = look.Density + 0.12
		out.Haze = look.Haze + 1.2
		out.Glare = 0
		out.AirColor = look.AirColor:Lerp(rgb(150, 158, 170), 0.7 * day)
		out.Tint = look.Tint:Lerp(rgb(224, 232, 244), 0.6)
		out.Saturation = look.Saturation - 0.18
		out.SunRays = 0
		out.CloudColor = look.CloudColor:Lerp(rgb(128, 134, 146), 0.75)
		out.CloudCover = 0.86
	else -- Fog
		out.Density = look.Density + 0.3
		out.Haze = look.Haze + 2.6
		out.Glare = look.Glare * 0.3
		out.AirColor = look.AirColor:Lerp(rgb(214, 218, 222), 0.75 * day)
		out.AirDecay = look.AirDecay:Lerp(rgb(170, 176, 184), 0.6 * day)
		out.Saturation = look.Saturation - 0.1
		out.SunRays = look.SunRays * 0.3
		out.CloudCover = math.max(look.CloudCover, 0.7)
	end
	return out :: Look
end

function Sky.WithWeather(look: Look, kind: string, amount: number): Look
	if amount <= 0 or (kind ~= "Rain" and kind ~= "Fog") then
		return look
	end
	local target = weatherTarget(look, kind)
	local out: any = {}
	for key, value in look :: any do
		out[key] = mix(value, (target :: any)[key], math.clamp(amount, 0, 1))
	end
	return out :: Look
end

return Sky
