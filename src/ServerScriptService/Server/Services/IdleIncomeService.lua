--!strict
-- Passive income for the equipped Brainrot: every `Constants.IDLE_TICK_SECONDS`
-- this awards Coins scaled by the equipped pet's rarity, so a Legendary feels
-- meaningfully better to have equipped than a Common even when nobody is
-- fighting. Nothing equipped ⇒ no income; that's the incentive to equip.
--
-- Performance contract: ONE shared loop for every player, not a
-- `task.spawn` per player. A per-player loop leaks (nothing ever cancels it
-- cleanly on PlayerRemoving without extra bookkeeping) and doesn't scale past
-- a handful of concurrent players; a single ticking loop that iterates
-- `Players:GetPlayers()` does the same job in O(players) per tick with one
-- thread total.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local IdleIncomeService = {}

-- `StoreService` (owned by a different agent) exposes
-- `StoreService.GetIdleIncomeMultiplier(player)` for the "IdleIncome" store
-- upgrade. That file may not exist yet - or may change shape - independently
-- of this one, since it's owned and edited by a different system. Requiring
-- it defensively (FindFirstChild + pcall) means a missing/broken sibling
-- service degrades idle income to "no store bonus" instead of breaking it
-- entirely for every player.
local storeService: any = nil
do
	local servicesFolder = script.Parent
	local moduleScript = servicesFolder:FindFirstChild("StoreService")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			storeService = result
		else
			warn("[IdleIncomeService] StoreService present but failed to require; idle income store bonus disabled:", result)
		end
	end
end

-- Falls back to a 1x (no bonus) multiplier whenever StoreService isn't
-- available or errors, so a broken/missing sibling never zeroes out idle
-- income entirely - it just loses the store-upgrade bonus on top of it.
local function idleIncomeStoreMultiplier(player: Player): number
	if not storeService or type(storeService.GetIdleIncomeMultiplier) ~= "function" then
		return 1
	end
	local ok, multiplier = pcall(storeService.GetIdleIncomeMultiplier, player)
	if not ok or type(multiplier) ~= "number" or multiplier <= 0 then
		return 1
	end
	return multiplier
end

-- Fractional coin remainders, so a Common pet (0.5 coins/sec) doesn't round
-- to zero forever across a 5s tick. Accumulated in memory only - losing a
-- fraction of a coin on server crash/restart is an acceptable trade for not
-- persisting a throwaway float per player.
local remainders: { [Player]: number } = {}

-- Whether idle income should be suppressed for this player right now.
--
-- Design call: idle income is suppressed while a player is on a CTF team
-- (`player.Team` set), whether the round is actively in progress or between
-- rounds. Two reasons:
--   1. Combat rewards (Constants.CTF_REWARDS) should be the point of playing
--      CTF - passive coin drip competing for the player's attention during a
--      fight undercuts that, and duplicate "+N Coins" popups from idle ticks
--      would spam the same feedback channel CTF uses for its own rewards.
--   2. `player.Team` is the one piece of CTF state this service can read
--      without reaching into CTFService's internals (which aren't exposed
--      publicly and are owned by a different system) - checking it keeps
--      IdleIncomeService decoupled from CTF's implementation.
-- Idle income resumes automatically the moment a player leaves their team.
local function isSuppressedByActiveCTF(player: Player): boolean
	return player.Team ~= nil
end

local function tick(tickSeconds: number)
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if not profile then
			continue
		end

		if isSuppressedByActiveCTF(player) then
			continue
		end

		local equipped = DataService.GetEquipped(player)
		if not equipped then
			continue
		end

		local baseRate = Constants.IDLE_COINS_PER_SECOND[equipped.Rarity]
		if not baseRate or baseRate <= 0 then
			continue
		end

		local storeMultiplier = idleIncomeStoreMultiplier(player)
		local raw = (baseRate * storeMultiplier * tickSeconds) + (remainders[player] or 0)
		local whole = math.floor(raw)
		remainders[player] = raw - whole

		if whole > 0 then
			-- AwardCoins applies the Double Coins pass, rebirth bonus and
			-- timed boosts on top of this - IdleIncomeService must not apply
			-- any of that itself, only the store-specific idle multiplier
			-- above (which EconomyService has no notion of).
			EconomyService.AwardCoins(player, whole, "Idle")
		end
	end
end

function IdleIncomeService.Init()
	Players.PlayerRemoving:Connect(function(player)
		remainders[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.IDLE_TICK_SECONDS)
			local ok, err = pcall(tick, Constants.IDLE_TICK_SECONDS)
			if not ok then
				warn("[IdleIncomeService] tick errored:", err)
			end
		end
	end)
end

return IdleIncomeService
