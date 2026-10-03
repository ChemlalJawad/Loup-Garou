--!strict
-- The 24-hour clock: moves Lighting.ClockTime (which replicates; each
-- client paints the sky from it), says when it's night, and tells everyone
-- when night falls and when the sun comes back.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Broadcast = require(script.Parent.Broadcast)

local DayNightService = {}

local D = Config.DayNight

function DayNightService.IsNight(): boolean
	local clock = Lighting.ClockTime
	return clock >= D.NightStart or clock < D.NightEnd
end

-- How much faster giants walk right now.
function DayNightService.GiantSpeed(): number
	return if DayNightService.IsNight() then D.NightSpeed else 1
end

function DayNightService.Init()
	Lighting.ClockTime = D.StartTime
	local hoursPerSecond = 24 / (D.DayMinutes * 60)
	local wasNight = DayNightService.IsNight()
	local pending = 0
	RunService.Heartbeat:Connect(function(dt: number)
		pending += dt
		if pending < 0.2 then
			return
		end
		Lighting.ClockTime = (Lighting.ClockTime + pending * hoursPerSecond) % 24
		pending = 0
		local night = DayNightService.IsNight()
		if night ~= wasNight then
			wasNight = night
			if night then
				Broadcast.Announce("NIGHT FALLS", "The giants' eyes glow in the dark... and they move faster", "Danger")
			else
				Broadcast.Announce("DAWN", "The sun is up - the giants slow down", "Gold")
			end
		end
	end)
end

return DayNightService
