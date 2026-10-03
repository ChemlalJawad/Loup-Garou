--!strict
-- Paints the sky from the server's clock, on this client only:
--   * light, atmosphere, colour grade, bloom, sun rays and clouds follow
--     the hour (Sky.lua): blue noon, gold and red sunset, dark blue night
--     with stars and a big moon;
--   * at night every lamp lantern and torch lights up (fire and light),
--     4 windows in 10 glow warm, and the giants' tiny pupils burn orange.
-- Lights change only when night falls or ends, not every frame.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Sky = require(ReplicatedStorage.Shared.Sky)

local SkyController = {}

local WINDOW_GLOW = Color3.fromRGB(255, 196, 120)
local EYE_GLOW = Color3.fromRGB(255, 110, 40)

local windowDay: { [BasePart]: Color3 } = {}
local lit = false

local function setLamp(part: Instance, on: boolean)
	if not part:IsA("BasePart") then
		return
	end
	for _, child in part:GetChildren() do
		if child:IsA("PointLight") then
			child.Enabled = on
		elseif child:IsA("Fire") then
			child.Enabled = on
		end
	end
	if part.Name == "Lantern" then
		part.Material = if on then Enum.Material.Neon else Enum.Material.Glass
	end
end

local function setWindow(part: Instance, on: boolean)
	if not part:IsA("BasePart") then
		return
	end
	if not windowDay[part] then
		windowDay[part] = part.Color
	end
	part.Color = if on then WINDOW_GLOW else windowDay[part]
	part.Material = if on then Enum.Material.Neon else Enum.Material.Glass
end

local function setEyes(giant: Instance, on: boolean)
	for _, name in { "Pupil1", "Pupil2" } do
		local pupil = giant:FindFirstChild(name)
		if pupil and pupil:IsA("BasePart") then
			pupil.Color = if on then EYE_GLOW else Color3.fromRGB(30, 25, 25)
			pupil.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function setAll(on: boolean)
	lit = on
	for _, part in CollectionService:GetTagged(Config.Tags.NightLight) do
		setLamp(part, on)
	end
	for _, part in CollectionService:GetTagged(Config.Tags.LitWindow) do
		setWindow(part, on)
	end
	for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
		setEyes(giant, on)
	end
end

function SkyController.Init()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	grade.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Parent = Lighting
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Parent = Lighting

	-- Anything that turns up later (new giants, streamed parts) matches the hour.
	for _, tag in { Config.Tags.NightLight, Config.Tags.LitWindow } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
			if tag == Config.Tags.NightLight then
				setLamp(part, lit)
			else
				setWindow(part, lit)
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Giant):Connect(function(giant)
		task.delay(0.5, function()
			setEyes(giant, lit)
		end)
	end)
	setAll(false)

	local D = Config.DayNight
	RunService.RenderStepped:Connect(function()
		local clock = Lighting.ClockTime
		local look = Sky.At(clock)
		Lighting.Brightness = look.Brightness
		Lighting.ExposureCompensation = look.Exposure
		Lighting.Ambient = look.Ambient
		Lighting.OutdoorAmbient = look.OutdoorAmbient
		Lighting.ColorShift_Top = look.ShiftTop
		atmosphere.Density = look.Density
		atmosphere.Haze = look.Haze
		atmosphere.Glare = look.Glare
		atmosphere.Color = look.AirColor
		atmosphere.Decay = look.AirDecay
		grade.TintColor = look.Tint
		grade.Saturation = look.Saturation
		grade.Contrast = look.Contrast
		bloom.Intensity = look.Bloom
		rays.Intensity = look.SunRays
		local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
		if clouds then
			clouds.Color = look.CloudColor
			clouds.Cover = look.CloudCover
		end
		local night = clock >= D.NightStart - 0.4 or clock < D.NightEnd + 0.3
		if night ~= lit then
			setAll(night)
		end
	end)
end

return SkyController
