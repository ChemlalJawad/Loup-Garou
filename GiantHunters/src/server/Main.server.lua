--!strict
-- Server boot: remotes first (everything else waits on them), then the
-- district, then saving and position tracking, giants, hunters, progression
-- (Marks, upgrades, challenges, looks), cannons, and the round loop.

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
local ProgressService = require(script.Parent.ProgressService)

local world = MapBuilder.Build()
DataService.Init()
Motion.Init()
DayNightService.Init()
GiantService.Init(world.GiantSpawns)
ShifterService.Init()
HunterService.Init(world.Spawn)
ProgressService.Init(world.Spawn) -- (after HunterService: it builds on its events)
require(script.Parent.LevelService).Init() -- XP and levels (same events)
CannonService.Init()
WaveService.Init()
require(script.Parent.WeatherService).Init()
-- Titan powers don't outlast the round they were won in.
WaveService.RoundEnded.Event:Connect(ShifterService.ClearPowers)
WaveService.DistrictFallen.Event:Connect(ShifterService.ClearPowers)

-- The shop's gear, techniques and titan forms (Marks and levels are in by
-- now), and the techniques themselves.
require(script.Parent.ShopService).Init()
require(script.Parent.TechniqueService).Init()

print(`[{Config.GAME_NAME}] server ready`)
