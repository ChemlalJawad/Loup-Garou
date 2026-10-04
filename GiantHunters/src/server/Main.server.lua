--!strict
-- Server boot: remotes first (everything else waits on them), then the
-- district, then saving and position tracking, giants, hunters, cannons,
-- and the round loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in Config.Remotes do
	local event = Instance.new("RemoteEvent")
	event.Name = name :: string
	event.Parent = remotes
end
remotes.Parent = ReplicatedStorage

local MapBuilder = require(script.Parent.MapBuilder)
local DataService = require(script.Parent.DataService)
local Motion = require(script.Parent.Motion)
local DayNightService = require(script.Parent.DayNightService)
local ShifterService = require(script.Parent.ShifterService)
local GiantService = require(script.Parent.GiantService)
local HunterService = require(script.Parent.HunterService)
local CannonService = require(script.Parent.CannonService)
local WaveService = require(script.Parent.WaveService)

local world = MapBuilder.Build()
DataService.Init()
Motion.Init()
DayNightService.Init()
GiantService.Init(world.GiantSpawns)
ShifterService.Init()
HunterService.Init(world.Spawn)
CannonService.Init()
WaveService.Init()
require(script.Parent.WeatherService).Init()
-- Titan powers don't outlast the round they were won in.
WaveService.RoundEnded.Event:Connect(ShifterService.ClearPowers)
WaveService.DistrictFallen.Event:Connect(ShifterService.ClearPowers)

print(`[{Config.GAME_NAME}] server ready`)
