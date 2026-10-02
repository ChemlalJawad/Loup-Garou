--!strict
-- Rounds and waves.
--
-- A round: a breather, then the Wallbreaker kicks the south gate in, then
-- waves pour through the breach (the last one brings an Armored Giant).
-- Clear them all and the district is saved: the gate is rebuilt and the
-- next round is a little harder. If everyone leaves, it all resets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)
local Wall = require(script.Parent.World.Wall)
local Broadcast = require(script.Parent.Broadcast)

local WaveService = {}

WaveService.RoundStarted = Instance.new("BindableEvent") -- (round)
WaveService.RoundEnded = Instance.new("BindableEvent") -- (round)

local waveEvent: RemoteEvent
local state = { Round = 1, Wave = 0, Phase = "Intermission", Countdown = 0 }

local function broadcast()
	waveEvent:FireAllClients({
		Round = state.Round,
		Wave = state.Wave,
		Waves = Config.Waves.WavesPerRound,
		Alive = GiantService.AliveCount(),
		Phase = state.Phase,
		Countdown = state.Countdown,
	})
end

local function empty(): boolean
	return #Players:GetPlayers() == 0
end

local function countdown(seconds: number, phase: string)
	state.Phase = phase
	for t = seconds, 1, -1 do
		state.Countdown = t
		broadcast()
		task.wait(1)
	end
	state.Countdown = 0
end

-- Until the wave is cleared; false if everyone left meanwhile.
local function fight(): boolean
	state.Phase = "Fight"
	while GiantService.AliveCount() > 0 do
		broadcast()
		task.wait(1)
		if empty() then
			return false
		end
	end
	return true
end

local function reset()
	GiantService.ClearAll()
	Wall.Repair()
	state.Round = 1
	state.Wave = 0
end

-- One round; false if the field emptied part way.
local function round(): boolean
	state.Wave = 0
	state.Phase = "Breach"
	broadcast()
	WaveService.RoundStarted:Fire(state.Round)
	if not Wall.IsBreached() then
		GiantService.RunWallbreaker()
	end
	for wave = 1, Config.Waves.WavesPerRound do
		if wave > 1 then
			countdown(Config.Waves.Intermission, "Intermission")
		end
		state.Wave = wave
		local roster = Config.WaveRoster(state.Round, wave)
		local boss = wave == Config.Waves.WavesPerRound
		Broadcast.Announce(`WAVE {wave}`, if boss then "An Armored Giant is coming - crack its nape plate!" else `{#roster} giants incoming`, if boss then "Gold" else "Danger")
		for _, kindName in roster do
			GiantService.SpawnGiant(kindName)
			task.wait(0.5)
		end
		if not fight() then
			return false
		end
	end
	state.Phase = "Victory"
	broadcast()
	Broadcast.Announce("DISTRICT SAVED!", `Round {state.Round} cleared - the gate is being rebuilt`, "Gold")
	WaveService.RoundEnded:Fire(state.Round)
	task.wait(5)
	Wall.Repair()
	state.Round += 1
	state.Wave = 0
	return true
end

function WaveService.Init()
	waveEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Wave) :: RemoteEvent
	task.spawn(function()
		local first = true
		while true do
			if empty() then
				task.wait(1)
				continue
			end
			countdown(if first then Config.Waves.FirstDelay else Config.Waves.BetweenRounds, "Intermission")
			first = false
			if empty() or not round() then
				reset()
				first = true
			end
		end
	end)
end

return WaveService
