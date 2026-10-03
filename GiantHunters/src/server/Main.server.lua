--!strict
-- Server boot: remotes first (everything else waits on them), then the
-- district, then giants, hunters, cannons, and the round loop.

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
local DayNightService = require(script.Parent.DayNightService)
local ShifterService = require(script.Parent.ShifterService)
local GiantService = require(script.Parent.GiantService)
local HunterService = require(script.Parent.HunterService)
local CannonService = require(script.Parent.CannonService)
local WaveService = require(script.Parent.WaveService)

local world = MapBuilder.Build()
DayNightService.Init()
GiantService.Init(world.GiantSpawns)
ShifterService.Init()
HunterService.Init()
CannonService.Init()
WaveService.Init()

print(`[{Config.GAME_NAME}] server ready`)
