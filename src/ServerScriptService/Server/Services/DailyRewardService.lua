--!strict
-- Server-authoritative daily login streak. Calendar-day semantics (UTC), not
-- "24 hours since last claim": a player who claims at 23:59 UTC and again at
-- 00:01 UTC has completed two different days, which is what players expect
-- from a "daily" reward and avoids the slow drift a rolling 24h window causes
-- as they claim at slightly different times each session.
--
-- Streak rule: claiming within Constants.DAILY_STREAK_RESET_HOURS (48h) of
-- the previous claim increments the streak (missing exactly one day is
-- forgiven); claiming later than that resets the streak to day 1. Days past
-- DailyConfig.MaxDay() keep paying the final tier (see DailyConfig).
--
-- Request/response contract (see Constants.REMOTE_NAMES.Daily):
--   Server fires StateUpdated({ Streak, Claimable, SecondsUntilNext, NextRewardDay, MaxDay })
--     on ProfileLoaded and after every claim.
--   Client fires ClaimReward()
--   Server fires ClaimResult({ Success, Reason?, Streak?, Reward? })

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local DailyConfig = require(ReplicatedStorage.Shared.Daily.DailyConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local DailyRewardService = {}

type ClaimFailureReason = "ProfileNotLoaded" | "NotClaimable"

export type DailyState = {
	Streak: number, -- confirmed streak from the last successful claim
	Claimable: boolean,
	SecondsUntilNext: number, -- 0 when Claimable is true
	NextRewardDay: number, -- which reward tier the *next* claim would pay (for card highlighting)
	MaxDay: number,
}

type Evaluation = {
	Claimable: boolean,
	NextStreak: number, -- streak that would result from claiming right now
	SecondsUntilNext: number,
}

local SECONDS_PER_DAY = 24 * 60 * 60
local STREAK_RESET_SECONDS = Constants.DAILY_STREAK_RESET_HOURS * 60 * 60

local stateUpdatedEvent: RemoteEvent
local claimResultEvent: RemoteEvent

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

-- "YYYY-MM-DD" in UTC. Roblox server clocks are UTC and os.date/os.time
-- already operate in UTC, but the "!" prefix is used anyway so this stays
-- correct even if that ever changes.
local function utcDateKey(timestamp: number): string
	local t = os.date("!*t", timestamp)
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

-- The UTC epoch second at which the calendar day containing `timestamp` rolls
-- over into the next one.
local function startOfNextUtcDay(timestamp: number): number
	local t = os.date("!*t", timestamp)
	t.hour, t.min, t.sec = 0, 0, 0
	local startOfThisDay = os.time(t)
	return startOfThisDay + SECONDS_PER_DAY
end

-- Pure evaluation of "what would happen if this player claimed right now",
-- shared by the state push (display) and the claim handler (authoritative
-- decision) so the two can never disagree about the rules.
local function evaluate(daily: { LastClaimAt: number, Streak: number }, now: number): Evaluation
	if daily.LastClaimAt <= 0 then
		return { Claimable = true, NextStreak = 1, SecondsUntilNext = 0 }
	end

	local claimable = utcDateKey(now) ~= utcDateKey(daily.LastClaimAt)
	local secondsUntilNext = if claimable then 0 else math.max(0, startOfNextUtcDay(daily.LastClaimAt) - now)

	local nextStreak = if (now - daily.LastClaimAt) <= STREAK_RESET_SECONDS then daily.Streak + 1 else 1

	return { Claimable = claimable, NextStreak = nextStreak, SecondsUntilNext = secondsUntilNext }
end

local function buildState(player: Player): DailyState?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local eval = evaluate(profile.Daily, os.time())
	return {
		Streak = profile.Daily.Streak,
		Claimable = eval.Claimable,
		SecondsUntilNext = eval.SecondsUntilNext,
		NextRewardDay = eval.NextStreak,
		MaxDay = DailyConfig.MaxDay(),
	}
end

local function pushState(player: Player)
	local state = buildState(player)
	if not state then
		return
	end
	stateUpdatedEvent:FireClient(player, state)
end

local function failClaim(player: Player, reason: ClaimFailureReason)
	claimResultEvent:FireClient(player, { Success = false, Reason = reason })
end

local function onClaimReward(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		failClaim(player, "ProfileNotLoaded")
		return
	end

	local now = os.time()
	local eval = evaluate(profile.Daily, now)
	if not eval.Claimable then
		failClaim(player, "NotClaimable")
		return
	end

	local newStreak = eval.NextStreak
	DataService.Mutate(player, function(p)
		p.Daily.LastClaimAt = now
		p.Daily.Streak = newStreak
	end)

	local reward = DailyConfig.RewardForDay(newStreak)
	EconomyService.AwardBundle(player, { Coins = reward.Coins, Gems = reward.Gems }, `Daily Reward (Day {newStreak})`)
	if reward.BoostName and reward.BoostSeconds then
		DataService.GrantBoost(player, reward.BoostName, reward.BoostSeconds)
	end

	claimResultEvent:FireClient(player, { Success = true, Streak = newStreak, Reward = reward })
	notify(player, `Day {newStreak} reward claimed!`, "Success")
	pushState(player)
end

local function onProfileLoaded(player: Player, _profile: DataService.Profile)
	pushState(player)

	local state = buildState(player)
	if state and state.Claimable then
		notify(player, "Your daily reward is ready!", "Info")
	end
end

function DailyRewardService.Init()
	stateUpdatedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Daily.StateUpdated)
	claimResultEvent = Net.GetEvent(Constants.REMOTE_NAMES.Daily.ClaimResult)

	Net.GetEvent(Constants.REMOTE_NAMES.Daily.ClaimReward).OnServerEvent:Connect(function(player)
		onClaimReward(player)
	end)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)

	for _, player in Players:GetPlayers() do
		if DataService.Get(player) then
			task.spawn(onProfileLoaded, player, DataService.Get(player) :: DataService.Profile)
		end
	end
end

return DailyRewardService
