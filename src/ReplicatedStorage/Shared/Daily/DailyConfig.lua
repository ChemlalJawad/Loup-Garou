--!strict
-- Wraps Constants.DAILY_REWARDS with the reward shapes the flat table can't
-- express (boost grants) plus a "day 7+ keeps paying day 7" repeat rule.
-- Constants.DAILY_REWARDS stays the source of truth for Coins/Gems per day;
-- this module is purely additive on top of it and must never diverge from it.
--
-- Owned by DailyRewardService/DailyController (system #7). Pure/stateless:
-- no DataService or Net requires here, just data + lookup helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local DailyConfig = {}

export type DailyReward = {
	Day: number,
	Coins: number,
	Gems: number,
	-- Boost name matches an EconomyService.BOOST_* constant (e.g. "Luck2x"),
	-- granted via DataService.GrantBoost. nil = no boost on this day.
	BoostName: string?,
	BoostSeconds: number?,
}

-- Extra boost grants layered onto specific days, on top of whatever
-- Constants.DAILY_REWARDS already pays for that day. Keyed by Day.
local boostByDay: { [number]: { Name: string, Seconds: number } } = {
	[5] = { Name = "Luck2x", Seconds = 30 * 60 }, -- 30 min Luck2x, as specced
	[7] = { Name = "Coins2x", Seconds = 60 * 60 }, -- capstone day gets a Coins2x hour too
}

local rewards: { DailyReward } = {}
for _, tier in Constants.DAILY_REWARDS do
	local boost = boostByDay[tier.Day]
	local reward: DailyReward = {
		Day = tier.Day,
		Coins = tier.Coins,
		Gems = tier.Gems,
		BoostName = if boost then boost.Name else nil,
		BoostSeconds = if boost then boost.Seconds else nil,
	}
	table.insert(rewards, reward)
end
table.sort(rewards, function(a, b)
	return a.Day < b.Day
end)
DailyConfig.Rewards = rewards

-- The highest day tier defined (7, per Constants.DAILY_REWARDS today). Streak
-- days beyond this keep paying this tier - see RewardForDay.
function DailyConfig.MaxDay(): number
	return #rewards
end

-- Returns the reward tier for `day`. Days past MaxDay() clamp to the final
-- tier so a long streak keeps paying out instead of falling off a cliff once
-- a player passes day 7.
function DailyConfig.RewardForDay(day: number): DailyReward
	local maxDay = DailyConfig.MaxDay()
	local clamped = math.clamp(day, 1, maxDay)
	return rewards[clamped]
end

return DailyConfig
