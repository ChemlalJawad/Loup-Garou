--!strict
-- The single funnel every Coins/Gems/XP reward flows through, so that
-- multipliers (Double Coins game pass, rebirth bonus, timed boosts) apply
-- everywhere automatically instead of each system remembering to check them.
--
-- Before this existed, DataService.AddCoins was called directly from CTF and
-- egg-sell paths, which meant the Double Coins pass silently did nothing.
-- Rule going forward: gameplay systems call EconomyService.AwardCoins /
-- AwardXP, never DataService.AddCoins, for *earned* currency. Direct
-- DataService.AddCoins stays correct only for purchased currency (Robux
-- products), which must not be multiplied.
--
-- Also owns level/XP progression and rebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(ServerScriptService.Server.Services.DataService)

local EconomyService = {}

export type MultiplierBreakdown = {
	Total: number,
	GamePass: number,
	Rebirth: number,
	Boost: number,
}

-- Boost names EconomyService itself understands. Other systems grant them via
-- DataService.GrantBoost(player, name, seconds).
EconomyService.BOOST_COINS_2X = "Coins2x"
EconomyService.BOOST_XP_2X = "XP2x"
EconomyService.BOOST_LUCK_2X = "Luck2x"

-- Fired as (player, profile) after a level-up so other systems (quests,
-- unlocks, VFX) can react without polling.
EconomyService.LeveledUp = Instance.new("BindableEvent")

local economyStateEvent: RemoteEvent
local rewardPopupEvent: RemoteEvent
local rebirthResultEvent: RemoteEvent

-- XP required to advance *from* `level` to `level + 1`.
function EconomyService.XPForNextLevel(level: number): number
	if level >= Constants.MAX_LEVEL then
		return math.huge
	end
	return math.floor(Constants.LEVEL_XP_BASE * (level ^ Constants.LEVEL_XP_EXPONENT))
end

function EconomyService.CoinMultiplier(player: Player): MultiplierBreakdown
	local profile = DataService.Get(player)
	if not profile then
		return { Total = 1, GamePass = 1, Rebirth = 1, Boost = 1 }
	end

	local gamePass = if profile.Perks.DoubleCoins then 2 else 1
	local rebirth = 1 + (profile.Rebirths * Constants.REBIRTH_COIN_MULTIPLIER_PER)
	local boost = if DataService.HasBoost(player, EconomyService.BOOST_COINS_2X) then 2 else 1

	return {
		Total = gamePass * rebirth * boost,
		GamePass = gamePass,
		Rebirth = rebirth,
		Boost = boost,
	}
end

function EconomyService.XPMultiplier(player: Player): number
	return if DataService.HasBoost(player, EconomyService.BOOST_XP_2X) then 2 else 1
end

-- True when the player's egg rolls should use boosted odds. EggService reads
-- this instead of checking the DoubleLuck perk directly, so a timed luck boost
-- and the permanent game pass both work through one code path.
function EconomyService.HasLuckBoost(player: Player): boolean
	return DataService.GetPerk(player, "DoubleLuck") or DataService.HasBoost(player, EconomyService.BOOST_LUCK_2X)
end

local function pushState(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	economyStateEvent:FireClient(player, {
		Coins = profile.Coins,
		Gems = profile.Gems,
		XP = profile.XP,
		Level = profile.Level,
		XPForNext = EconomyService.XPForNextLevel(profile.Level),
		Rebirths = profile.Rebirths,
		CoinMultiplier = EconomyService.CoinMultiplier(player).Total,
		InventoryUsed = #profile.OwnedBrainrots,
		InventorySlots = profile.InventorySlots,
	})
end

EconomyService.PushState = pushState

-- Awards earned Coins with all multipliers applied. `reason` is a short string
-- used for the floating "+N Coins" client popup (e.g. "Flag Capture", "Idle").
-- Returns the amount actually granted.
function EconomyService.AwardCoins(player: Player, baseAmount: number, reason: string?): number
	if baseAmount <= 0 then
		return 0
	end
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	local multiplier = EconomyService.CoinMultiplier(player).Total
	local granted = math.floor(baseAmount * multiplier + 0.5)

	DataService.AddCoins(player, granted)
	DataService.Mutate(player, function(p)
		p.Stats.CoinsEarned += granted
	end)

	if reason then
		rewardPopupEvent:FireClient(player, { Currency = "Coins", Amount = granted, Reason = reason })
	end
	pushState(player)
	return granted
end

function EconomyService.AwardGems(player: Player, amount: number, reason: string?): number
	if amount <= 0 then
		return 0
	end
	-- Gems are deliberately not multiplied: they're the premium currency, and
	-- multiplying them would let a coin-focused pass inflate paid currency.
	DataService.AddGems(player, amount)
	if reason then
		rewardPopupEvent:FireClient(player, { Currency = "Gems", Amount = amount, Reason = reason })
	end
	pushState(player)
	return amount
end

-- Awards XP with boosts applied, handling level-ups (including multi-level
-- jumps from one large award). Returns the number of levels gained.
function EconomyService.AwardXP(player: Player, baseAmount: number, reason: string?): number
	if baseAmount <= 0 then
		return 0
	end
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	local granted = math.floor(baseAmount * EconomyService.XPMultiplier(player) + 0.5)
	local levelsGained = 0

	DataService.Mutate(player, function(p)
		p.XP += granted
		while p.Level < Constants.MAX_LEVEL do
			local needed = EconomyService.XPForNextLevel(p.Level)
			if p.XP < needed then
				break
			end
			p.XP -= needed
			p.Level += 1
			levelsGained += 1
		end
		if p.Level >= Constants.MAX_LEVEL then
			p.XP = 0
		end
	end)

	if levelsGained > 0 then
		EconomyService.LeveledUp:Fire(player, DataService.Get(player))
		Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(
			player,
			`Level up! You are now level {profile.Level}.`,
			"Success"
		)
	end

	if reason then
		rewardPopupEvent:FireClient(player, { Currency = "XP", Amount = granted, Reason = reason })
	end
	pushState(player)
	return levelsGained
end

-- Convenience for the common "reward table" shape used by Constants.CTF_REWARDS
-- and quest/daily configs: { Coins = n?, Gems = n?, XP = n? }.
function EconomyService.AwardBundle(player: Player, bundle: { Coins: number?, Gems: number?, XP: number? }, reason: string?)
	if bundle.Coins then
		EconomyService.AwardCoins(player, bundle.Coins, reason)
	end
	if bundle.Gems then
		EconomyService.AwardGems(player, bundle.Gems, reason)
	end
	if bundle.XP then
		EconomyService.AwardXP(player, bundle.XP, reason)
	end
end

function EconomyService.CanRebirth(player: Player): (boolean, string?)
	local profile = DataService.Get(player)
	if not profile then
		return false, "ProfileNotLoaded"
	end
	if profile.Rebirths >= Constants.REBIRTH_MAX then
		return false, "MaxRebirths"
	end
	if profile.Level < Constants.REBIRTH_MIN_LEVEL then
		return false, "LevelTooLow"
	end
	return true, nil
end

-- Resets level/XP/Coins in exchange for +1 rebirth (a permanent additive coin
-- multiplier). Deliberately keeps the Brainrot collection and the index: this
-- is a soft prestige, not a wipe, so a rebirth never destroys a Secret pull.
function EconomyService.TryRebirth(player: Player): boolean
	local allowed, reason = EconomyService.CanRebirth(player)
	if not allowed then
		rebirthResultEvent:FireClient(player, { Success = false, Reason = reason })
		return false
	end

	DataService.Mutate(player, function(p)
		p.Rebirths += 1
		p.Level = 1
		p.XP = 0
		p.Coins = Constants.STARTING_COINS
	end)

	local profile = DataService.Get(player)
	local newMultiplier = EconomyService.CoinMultiplier(player).Total
	rebirthResultEvent:FireClient(player, {
		Success = true,
		Rebirths = profile and profile.Rebirths or 0,
		CoinMultiplier = newMultiplier,
	})
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(
		player,
		`Rebirth complete! Coin multiplier is now x{string.format("%.2f", newMultiplier)}.`,
		"Success"
	)
	pushState(player)
	return true
end

function EconomyService.Init()
	economyStateEvent = Net.GetEvent(Constants.REMOTE_NAMES.Economy.StateUpdated)
	rewardPopupEvent = Net.GetEvent(Constants.REMOTE_NAMES.Economy.RewardPopup)
	rebirthResultEvent = Net.GetEvent(Constants.REMOTE_NAMES.Economy.RebirthResult)

	Net.GetEvent(Constants.REMOTE_NAMES.Economy.RequestRebirth).OnServerEvent:Connect(function(player)
		EconomyService.TryRebirth(player)
	end)

	DataService.ProfileLoaded:Connect(function(player)
		pushState(player)
	end)

	-- Keep the client's economy HUD in sync with any profile mutation, whoever
	-- caused it. Throttled per player so a burst of mutations (e.g. a x10 hatch
	-- granting 10 entries) collapses into one push instead of ten.
	local pushQueued: { [Player]: boolean } = {}
	DataService.ProfileChanged:Connect(function(player: Player)
		if pushQueued[player] then
			return
		end
		pushQueued[player] = true
		task.defer(function()
			pushQueued[player] = nil
			if player.Parent then
				pushState(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pushQueued[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		if DataService.Get(player) then
			pushState(player)
		end
	end
end

return EconomyService
