--!strict
-- Levels: experience from play, 1 to Config.Leveling.MaxLevel, saved.
--
-- XP comes from takedowns (scaled by the giant's Points), clean cuts, trips
-- and dazes, cracked armour, rescues, cannon hits, titan fights, rounds seen
-- through, daily challenges (ProgressService calls LevelService.Add), and a
-- trickle from training dummies (capped a minute). Numbers: Config.Leveling.
--
-- Published as player attributes "Level", "XP" (progress within the level)
-- and "XPNext" (0 at the top), plus a "Level" column on the leaderboard.
-- Stats.lua turns the level into small bonuses (speed, gas, nape damage).
-- A level-up gets the hunter a big announcement, a line in everyone's feed
-- and some Marks (more every 5th level; ProgressService pays them out via
-- LevelService.LeveledUp). Each gain also goes to its hunter as a floating
-- "+XP" (Config.Remotes.XP), gathered over a moment so a takedown shows as
-- one number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DataService = require(script.Parent.DataService)
local GiantService = require(script.Parent.GiantService)
local HunterService = require(script.Parent.HunterService)
local ShifterService = require(script.Parent.ShifterService)
local Broadcast = require(script.Parent.Broadcast)

local LevelService = {}

LevelService.LeveledUp = Instance.new("BindableEvent") -- (player, level, marks)
-- Every gain, boosts included, even at the top level (SeasonService's season XP).
LevelService.Gained = Instance.new("BindableEvent") -- (player, amount)

type State = {
	Ready: boolean, -- the saved profile is loaded
	Pending: number, -- XP earned while it was loading
	Shown: number, -- XP gathered for the next floating "+XP"
	Dummy: number, -- dummy cuts counted this minute
	DummyMinute: number,
}

local L = Config.Leveling
local X = Config.Leveling.XP
local NAPE_RESULTS = { Hit = true, Defeated = true, Armor = true, ArmorBroken = true }
local ASSIST_XP = { Trip = X.Trip, Daze = X.Daze, Rescue = X.Rescue, Cannon = X.Cannon, Armor = X.Armor }

local states: { [Player]: State } = {}
local remote: RemoteEvent

local function levelStat(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Level")
	return if value and value:IsA("IntValue") then value else nil
end

local function publish(player: Player, level: number, xp: number)
	player:SetAttribute("Level", level)
	player:SetAttribute("XP", xp)
	player:SetAttribute("XPNext", Stats.XPNext(level))
	local stat = levelStat(player)
	if stat then
		stat.Value = level
	end
end

local function marksFor(level: number): number
	return if level % L.MilestoneEvery == 0 then L.MilestoneMarks else L.MarksPerLevel
end

local function celebrate(player: Player, level: number)
	local marks = marksFor(level)
	local milestone = level % L.MilestoneEvery == 0
	local subtitle = if level >= L.MaxLevel
		then `The top level! +{marks} Marks`
		else `Faster, more gas, sharper cuts! +{marks} Marks`
	Broadcast.Announce(`LEVEL {level}!`, subtitle, "Gold", player)
	Broadcast.Feed(`{player.DisplayName} reached level {level}!`, if milestone then "Gold" else "Good")
	remote:FireClient(player, "LevelUp", level, marks)
	LevelService.LeveledUp:Fire(player, level, marks)
end

-- Adds XP into the saved profile, levelling up as often as it fills.
local function apply(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local level = math.clamp(profile.Level, 1, L.MaxLevel)
	local xp = profile.XP + amount
	local reached: { number } = {}
	while level < L.MaxLevel and xp >= Stats.XPNext(level) do
		xp -= Stats.XPNext(level)
		level += 1
		table.insert(reached, level)
	end
	if level >= L.MaxLevel then
		xp = 0
	end
	profile.Level, profile.XP = level, xp
	DataService.Touch(player)
	publish(player, level, xp)
	for _, at in reached do
		celebrate(player, at)
	end
end

-- Gives `player` some XP (whole numbers; `reason` is just for the client).
function LevelService.Add(player: Player, amount: number, _reason: string?)
	local state = states[player]
	-- A Server XP Boost (MonetizationService): the Workspace's "XPBoostUntil".
	local boostUntil = Workspace:GetAttribute("XPBoostUntil")
	if type(boostUntil) == "number" and boostUntil > Workspace:GetServerTimeNow() then
		amount *= Config.Monetization.XPBoost.Multiplier
	end
	amount = math.floor(amount)
	if not state or amount <= 0 or not player.Parent then
		return
	end
	LevelService.Gained:Fire(player, amount)
	if state.Ready and (player:GetAttribute("Level") or 1) :: number >= L.MaxLevel then
		return -- (the top: nothing more to fill)
	end
	if state.Ready then
		apply(player, amount)
	else
		state.Pending += amount
	end
	-- The floating "+XP": gathered over a moment, then sent as one.
	local first = state.Shown == 0
	state.Shown += amount
	if first then
		task.delay(0.25, function()
			if states[player] == state and state.Shown > 0 and player.Parent then
				remote:FireClient(player, "XP", state.Shown)
			end
			state.Shown = 0
		end)
	end
end

local function onLoaded(player: Player)
	local state = states[player]
	local profile = DataService.Get(player)
	if not state or state.Ready or not profile then
		return
	end
	state.Ready = true
	profile.Level = math.clamp(profile.Level, 1, L.MaxLevel)
	if profile.Level >= L.MaxLevel then
		profile.XP = 0
	end
	publish(player, profile.Level, profile.XP)
	if state.Pending > 0 then
		local pending = state.Pending
		state.Pending = 0
		apply(player, pending)
	end
end

local function onPlayerAdded(player: Player)
	states[player] = { Ready = false, Pending = 0, Shown = 0, Dummy = 0, DummyMinute = 0 }
	publish(player, 1, 0)
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then
			onLoaded(player)
		end
	end)
	if player:GetAttribute("DataLoaded") then
		task.spawn(onLoaded, player)
	end
	-- (HunterService makes the leaderboard; fill in the column once it's there.)
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 30)
		if leaderstats and leaderstats:WaitForChild("Level", 10) then
			publish(player, Stats.Level(player), (player:GetAttribute("XP") or 0) :: number)
		end
	end)
end

function LevelService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.XP) :: RemoteEvent

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	GiantService.Defeated.Event:Connect(function(player: Player, kindName: string, clean: boolean)
		local kind = Config.GiantKinds[kindName]
		local xp = (if kind then kind.Points else 1) * X.TakedownPerPoint
		LevelService.Add(player, xp + (if clean then X.CleanTakedown else 0), "Takedown")
	end)
	GiantService.Assist.Event:Connect(function(player: Player, reason: string)
		LevelService.Add(player, ASSIST_XP[reason] or 0, reason)
	end)
	ShifterService.Scored.Event:Connect(function(player: Player, amount: number)
		LevelService.Add(player, amount * X.ShifterPoint, "Titan")
	end)
	HunterService.Slashed.Event:Connect(function(player: Player, outcome: string, info: any)
		local state = states[player]
		if not state or type(info) ~= "table" then
			return
		end
		if outcome == "Training" then
			local minute = os.time() // 60
			if minute ~= state.DummyMinute then
				state.DummyMinute, state.Dummy = minute, 0
			end
			if state.Dummy < X.DummyPerMinute then
				state.Dummy += 1
				LevelService.Add(player, X.Dummy, "Dummy")
			end
		elseif NAPE_RESULTS[outcome] and info.Clean == true then
			LevelService.Add(player, X.CleanCut, "CleanCut")
		end
	end)
end

return LevelService
