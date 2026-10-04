--!strict
-- The weather: long dry spells, and now and then a soft rain or a fog bank
-- for a few minutes. The server only picks it and sets the Workspace
-- attribute (Config.Weather.Attribute: "Clear", "Rain" or "Fog"), which
-- replicates; each client fades its own sky, rain and townsfolk into it
-- (client Weather.lua). A front never starts while someone on the server
-- is still doing the tutorial, and it's announced quietly in the feed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Broadcast = require(script.Parent.Broadcast)

local WeatherService = {}

local C = Config.Weather

local function set(kind: string)
	Workspace:SetAttribute(C.Attribute, kind)
end

-- Is anyone still learning the ropes? (TutorialDone is set by the server
-- once a player's save has loaded; nil means not loaded yet.)
local function tutorialRunning(): boolean
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("TutorialDone") ~= true then
			return true
		end
	end
	return false
end

function WeatherService.Current(): string
	return (Workspace:GetAttribute(C.Attribute) :: string?) or "Clear"
end

function WeatherService.Init()
	set("Clear")
	local rng = Random.new()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(C.ClearMinutes[1], C.ClearMinutes[2]) * 60)
			-- Hold off while someone's in the tutorial (or nobody's here).
			while #Players:GetPlayers() == 0 or tutorialRunning() do
				task.wait(10)
			end
			local rain = rng:NextNumber() < C.RainChance
			set(if rain then "Rain" else "Fog")
			Broadcast.Feed(if rain then "A soft rain drifts over the district." else "A fog bank rolls in from the Great Forest.", "Info")
			task.wait(rng:NextNumber(C.Minutes[1], C.Minutes[2]) * 60)
			set("Clear")
			Broadcast.Feed(if rain then "The rain has stopped." else "The fog lifts.", "Info")
		end
	end)
end

return WeatherService
