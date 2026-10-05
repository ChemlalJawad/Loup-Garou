--!strict
-- Rounds and waves, and the district's health.
--
-- A round: a breather, then the Wallbreaker kicks the south gate in, then
-- waves pour through the breach (the last one brings an Armored Giant).
-- Clear them all and the district is saved: the gate is rebuilt and the
-- next round is a little harder. If everyone leaves, it all resets.
--
-- More hunters, more giants (Config.WaveScale), and never more than
-- Config.Waves.MaxAlive on the field at once: the rest wait their turn.
-- A wave can't drag on: after Config.Waves.TimeLimit the giants storm into
-- town and far-off stragglers steam away.
--
-- The district has health (Config.District). It drains while giants are
-- inside the wall, and each time a hunter is grabbed or caught. At zero the
-- DISTRICT FALLS: the field is cleared, the gate rebuilt, and it's back to
-- round 1. It's full again at the start of every round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)
local Wall = require(script.Parent.World.Wall)
local Broadcast = require(script.Parent.Broadcast)

local WaveService = {}

WaveService.RoundStarted = Instance.new("BindableEvent") -- (round)
WaveService.RoundEnded = Instance.new("BindableEvent") -- (round): the district was saved
WaveService.DistrictFallen = Instance.new("BindableEvent") -- (round)
WaveService.WaveStarted = Instance.new("BindableEvent") -- (round, wave)

type Outcome = "Victory" | "Empty" | "Fallen"

local D = Config.District
local waveEvent: RemoteEvent
local state = { Round = 1, Wave = 0, Phase = "Intermission", Countdown = 0, District = D.Health, WaveEndsAt = 0 }

local function payload(): { [string]: any }
	return {
		Round = state.Round,
		Wave = state.Wave,
		Waves = Config.Waves.WavesPerRound,
		Alive = GiantService.AliveCount(),
		Phase = state.Phase,
		Countdown = state.Countdown,
		District = math.ceil(state.District),
		DistrictMax = D.Health,
		TimeLeft = if state.Phase == "Fight" then math.max(math.ceil(state.WaveEndsAt - os.clock()), 0) else nil,
	}
end

local function broadcast()
	waveEvent:FireAllClients(payload())
end

local function empty(): boolean
	return #Players:GetPlayers() == 0
end

local function fallen(): boolean
	return state.District <= 0
end

local function hurt(amount: number)
	if state.Phase ~= "Fight" or fallen() then
		return
	end
	state.District = math.max(state.District - amount, 0)
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

-- Until the wave is cleared (or the district falls, or everyone leaves).
local function fight(): Outcome?
	local hurried = false
	while GiantService.AliveCount() > 0 do
		if not hurried and os.clock() >= state.WaveEndsAt then
			hurried = true
			local gone = GiantService.Hurry(Config.Waves.StragglerRadius)
			Broadcast.Announce("THE GIANTS ARE STORMING IN!", if gone > 0 then "Stragglers have steamed away - stop the rest!" else "Time's up - stop them!", "Danger")
		end
		broadcast()
		task.wait(1)
		if empty() then
			return "Empty"
		end
		if fallen() then
			return "Fallen"
		end
	end
	return nil
end

local function reset()
	GiantService.ClearAll()
	Wall.Repair()
	state.Round = 1
	state.Wave = 0
	state.District = D.Health
end

-- One round, start to finish.
local function round(): Outcome
	state.Wave = 0
	state.District = D.Health
	state.Phase = "Breach"
	broadcast()
	GiantService.SetRound(state.Round) -- (the giants get a little sharper each round)
	WaveService.RoundStarted:Fire(state.Round)
	if not Wall.IsBreached() then
		GiantService.RunWallbreaker()
	end
	for wave = 1, Config.Waves.WavesPerRound do
		if wave > 1 then
			countdown(Config.Waves.Intermission, "Intermission")
		end
		state.Wave = wave
		state.Phase = "Fight"
		state.WaveEndsAt = os.clock() + Config.Waves.TimeLimit
		local roster = Config.WaveRoster(state.Round, wave, Config.WaveScale(#Players:GetPlayers()))
		local boss = wave == Config.Waves.WavesPerRound
		WaveService.WaveStarted:Fire(state.Round, wave)
		Broadcast.Announce(`WAVE {wave}`, if boss then "An Armored Giant is coming - crack its nape plate!" else `{#roster} giants incoming`, if boss then "Gold" else "Danger")
		for _, kindName in roster do
			-- Room on the field first.
			while GiantService.AliveCount() >= Config.Waves.MaxAlive do
				broadcast()
				task.wait(1)
				if empty() then
					return "Empty"
				elseif fallen() then
					return "Fallen"
				end
			end
			GiantService.SpawnGiant(kindName)
			task.wait(0.5)
			if empty() then
				return "Empty"
			elseif fallen() then
				return "Fallen"
			end
		end
		-- Sometimes the Beast Giant shows up too.
		if wave >= Config.Waves.BeastFromWave and not GiantService.HasKind("Beast") and math.random() < Config.Beast.Chance then
			GiantService.SpawnGiant("Beast")
		end
		local outcome: Outcome? = fight()
		if outcome then
			return outcome :: Outcome
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
	return "Victory"
end

-- The district fell: a pause to take it in, then everything back to round 1.
local function districtFallen()
	state.Phase = "Fallen"
	broadcast()
	Broadcast.Announce("DISTRICT FALLEN", `The giants overran the district in round {state.Round}. Regroup, hunters - back to round 1!`, "Danger")
	Broadcast.Feed("The district has fallen...", "Danger")
	WaveService.DistrictFallen:Fire(state.Round)
	GiantService.ClearAll()
	task.wait(D.FallenPause)
	reset()
end

function WaveService.Init()
	waveEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Wave) :: RemoteEvent

	-- Late joiners see where things stand straight away.
	Players.PlayerAdded:Connect(function(player)
		waveEvent:FireClient(player, payload())
	end)

	-- Giants inside the wall wear the district down.
	task.spawn(function()
		local step = 0.5
		while true do
			task.wait(step)
			if state.Phase == "Fight" then
				hurt(math.min(GiantService.InsideWeight() * D.DrainPerGiant, D.MaxDrain) * step)
			end
		end
	end)
	GiantService.Grabbed.Event:Connect(function(_player: Player, what: string)
		hurt(if what == "Caught" then D.CaughtDamage else D.GrabDamage)
	end)

	task.spawn(function()
		local first = true
		while true do
			if empty() then
				task.wait(1)
				continue
			end
			countdown(if first then Config.Waves.FirstDelay else Config.Waves.BetweenRounds, "Intermission")
			first = false
			if empty() then
				reset()
				first = true
				continue
			end
			local outcome = round()
			if outcome == "Fallen" then
				districtFallen()
			elseif outcome == "Empty" then
				reset()
				first = true
			end
		end
	end)
end

return WaveService
