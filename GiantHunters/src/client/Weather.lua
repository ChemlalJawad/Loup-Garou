--!strict
-- The weather on this client: follows the server's pick (the Workspace
-- attribute Config.Weather.Attribute) and fades it in and out over
-- FadeSeconds. SkyController blends the sky with Weather.Kind() and
-- Weather.Amount() (Sky.WithWeather); rain falls from one emitter riding
-- above the camera (default particle texture stretched into streaks, no
-- assets), lighter on phones. Kept clear during this player's tutorial.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Weather = {}

local C = Config.Weather
local kind = "Clear" -- the front showing (kept while it fades out)
local amount = 0

function Weather.Kind(): string
	return kind
end

-- 0 clear .. 1 full weather.
function Weather.Amount(): number
	return amount
end

function Weather.Raining(): boolean
	return kind == "Rain" and amount > 0.3
end

function Weather.Init()
	local player = Players.LocalPlayer
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- The rain cloud: an invisible slab that follows the camera.
	local cloud = Instance.new("Part")
	cloud.Name = "RainCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.CastShadow = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(150, 1, 150)
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Color = ColorSequence.new(Color3.fromRGB(200, 214, 232))
	rain.LightEmission = 0.15
	rain.Transparency = NumberSequence.new(0.45)
	rain.Size = NumberSequence.new(0.18)
	rain.Squash = NumberSequence.new(3) -- thin, stretched along the fall: streaks
	rain.Speed = NumberRange.new(90, 110)
	rain.Lifetime = NumberRange.new(0.9, 1.1)
	rain.SpreadAngle = Vector2.new(4, 4)
	rain.Rate = 0
	rain.Parent = cloud
	cloud.Parent = Workspace

	local maxRate = if phone then C.RainRate / 3 else C.RainRate
	RunService.RenderStepped:Connect(function(dt: number)
		local wanted = (Workspace:GetAttribute(C.Attribute) :: string?) or "Clear"
		local inTutorial = player:GetAttribute("TutorialDone") == false
		local goal = if wanted ~= "Clear" and not inTutorial then 1 else 0
		if goal > 0 and wanted ~= kind then
			-- A new front: fade the old one out first.
			if amount <= 0.01 or kind == "Clear" then
				kind = wanted
			else
				goal = 0
			end
		end
		local step = dt / C.FadeSeconds
		amount = if goal > amount then math.min(amount + step, goal) else math.max(amount - step, goal)
		if amount <= 0 and goal == 0 then
			kind = "Clear"
		end

		local camera = Workspace.CurrentCamera
		local raining = kind == "Rain" and amount > 0.02
		rain.Rate = if raining then maxRate * amount else 0
		if raining and camera then
			-- Ahead of the camera a little, so the streaks fill the view.
			local look = camera.CFrame.LookVector
			cloud.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(look.X, 0, look.Z) * 30 + Vector3.new(0, 60, 0))
		end
	end)
end

return Weather
