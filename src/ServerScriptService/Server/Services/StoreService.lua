--!strict
-- Server-authoritative in-game-currency Store: permanent upgrades, timed
-- boosts, and instant consumables, all purchasable with Coins or Gems only
-- (never Robux - that's ShopService's job). Every price is recomputed here
-- from StoreConfig; a client-sent tier/price/currency is never trusted.
--
-- Request/response contract (see Constants.REMOTE_NAMES.Store):
--   Client fires RequestPurchase(category: "Upgrade" | "Boost" | "Consumable", itemId: string)
--   Server fires PurchaseResult({ Success, Category, ItemId, NewTier?, Reason? })
--   Server fires StateUpdated({ Upgrades, Boosts }) on every change and on load.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local StoreConfig = require(ReplicatedStorage.Shared.Store.StoreConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local StoreService = {}

type PurchaseCategory = "Upgrade" | "Boost" | "Consumable"

type PurchaseFailureReason = "InvalidItem" | "MaxTier" | "NotEnoughCurrency" | "ProfileNotLoaded"

export type StoreState = {
	Upgrades: { [string]: number },
	Boosts: { [string]: number }, -- family ("Coins2x" | "XP2x" | "Luck2x") -> seconds remaining
}

-- Roblox's default Humanoid.WalkSpeed. The WalkSpeed upgrade adds on top of
-- this rather than replacing it outright.
local BASE_WALK_SPEED = 16

-- Maps a StoreConfig.BoostFamily to the exact boost-name constant
-- EconomyService/DataService.GrantBoost expects. Kept as an explicit table
-- (rather than assuming the family string equals the constant) so a rename on
-- either side fails loudly instead of silently mismatching.
local BOOST_NAME_BY_FAMILY: { [string]: string } = {
	Coins2x = EconomyService.BOOST_COINS_2X,
	XP2x = EconomyService.BOOST_XP_2X,
	Luck2x = EconomyService.BOOST_LUCK_2X,
}

local requestPurchaseEvent: RemoteEvent
local purchaseResultEvent: RemoteEvent
local stateUpdatedEvent: RemoteEvent

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

-- === Read helpers (safe to call before a profile has loaded) ================

function StoreService.GetUpgradeTier(player: Player, upgradeId: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return profile.Upgrades[upgradeId] or 0
end

-- Additive luck bonus from the LuckBoost upgrade tier, e.g. 0.03 for tier 3.
-- The Egg system adds this to its base luck roll.
function StoreService.GetLuckBonus(player: Player): number
	local def = StoreConfig.GetUpgrade("LuckBoost")
	if not def then
		return 0
	end
	local tier = StoreService.GetUpgradeTier(player, "LuckBoost")
	return tier * def.EffectPerTier
end

-- Multiplicative idle-income bonus from the IdleIncome upgrade tier, e.g.
-- 1.24 for tier 3 (1 + 3 * 0.08). Convenience helper for IdleIncomeService.
function StoreService.GetIdleIncomeMultiplier(player: Player): number
	local def = StoreConfig.GetUpgrade("IdleIncome")
	if not def then
		return 1
	end
	local tier = StoreService.GetUpgradeTier(player, "IdleIncome")
	return 1 + tier * def.EffectPerTier
end

-- === WalkSpeed side effect ===================================================
-- A respawned character resets Humanoid.WalkSpeed to the Roblox default, so
-- this must be reapplied on every CharacterAdded, not just at purchase time.

local function applyWalkSpeed(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local def = StoreConfig.GetUpgrade("WalkSpeed")
	local tier = StoreService.GetUpgradeTier(player, "WalkSpeed")
	local bonus = if def then tier * def.EffectPerTier else 0
	humanoid.WalkSpeed = BASE_WALK_SPEED + bonus
end

local function onCharacterAdded(player: Player, character: Model)
	applyWalkSpeed(player, character)
end

-- === State push ==============================================================

local function buildState(player: Player): StoreState?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	local upgradesCopy: { [string]: number } = {}
	for _, id in StoreConfig.UpgradeOrder do
		upgradesCopy[id] = profile.Upgrades[id] or 0
	end

	local boosts: { [string]: number } = {}
	for family, boostName in BOOST_NAME_BY_FAMILY do
		boosts[family] = DataService.BoostSecondsRemaining(player, boostName)
	end

	return {
		Upgrades = upgradesCopy,
		Boosts = boosts,
	}
end

local function pushState(player: Player)
	local state = buildState(player)
	if not state then
		return
	end
	stateUpdatedEvent:FireClient(player, state)
end

-- === Purchase handling ========================================================

local function trySpend(player: Player, currency: StoreConfig.CurrencyKind, amount: number): boolean
	if currency == "Gems" then
		return DataService.TrySpendGems(player, amount)
	end
	return DataService.TrySpendCoins(player, amount)
end

local FAILURE_MESSAGES: { [string]: string } = {
	InvalidItem = "That item isn't available.",
	MaxTier = "That upgrade is already at max tier.",
	NotEnoughCurrency = "You don't have enough currency for that.",
	ProfileNotLoaded = "Your data is still loading - try again in a moment.",
}

local function fail(player: Player, category: string, itemId: string, reason: PurchaseFailureReason)
	purchaseResultEvent:FireClient(player, {
		Success = false,
		Category = category,
		ItemId = itemId,
		Reason = reason,
	})
	notify(player, FAILURE_MESSAGES[reason] or "Purchase failed.", "Warning")
end

local function handleUpgradePurchase(player: Player, itemId: string)
	local def = StoreConfig.GetUpgrade(itemId)
	if not def then
		fail(player, "Upgrade", itemId, "InvalidItem")
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		fail(player, "Upgrade", itemId, "ProfileNotLoaded")
		return
	end

	local currentTier = profile.Upgrades[itemId] or 0
	if currentTier >= def.MaxTier then
		fail(player, "Upgrade", itemId, "MaxTier")
		return
	end

	local nextTier = currentTier + 1
	local price = def.PriceForTier(nextTier)

	if not trySpend(player, def.Currency, price) then
		fail(player, "Upgrade", itemId, "NotEnoughCurrency")
		return
	end

	DataService.Mutate(player, function(profileToMutate)
		profileToMutate.Upgrades[itemId] = nextTier
	end)

	if itemId == "InventorySlots" then
		DataService.AddInventorySlots(player, def.EffectPerTier)
	elseif itemId == "WalkSpeed" then
		local character = player.Character
		if character then
			applyWalkSpeed(player, character)
		end
	end
	-- IdleIncome and LuckBoost are read lazily via the helpers above; no
	-- immediate side effect needed beyond persisting the new tier.

	purchaseResultEvent:FireClient(player, {
		Success = true,
		Category = "Upgrade",
		ItemId = itemId,
		NewTier = nextTier,
	})
	notify(player, `{def.Name} upgraded to tier {nextTier}!`, "Success")
	pushState(player)
	EconomyService.PushState(player)
end

local function handleBoostPurchase(player: Player, itemId: string)
	local def = StoreConfig.GetBoost(itemId)
	if not def then
		fail(player, "Boost", itemId, "InvalidItem")
		return
	end

	local boostName = BOOST_NAME_BY_FAMILY[def.Family]
	if not boostName then
		warn(`[StoreService] no EconomyService boost constant mapped for family "{def.Family}"`)
		fail(player, "Boost", itemId, "InvalidItem")
		return
	end

	if not DataService.Get(player) then
		fail(player, "Boost", itemId, "ProfileNotLoaded")
		return
	end

	if not trySpend(player, def.Currency, def.Price) then
		fail(player, "Boost", itemId, "NotEnoughCurrency")
		return
	end

	DataService.GrantBoost(player, boostName, def.DurationSeconds)

	purchaseResultEvent:FireClient(player, {
		Success = true,
		Category = "Boost",
		ItemId = itemId,
	})
	notify(player, `{def.Name} activated!`, "Success")
	pushState(player)
	EconomyService.PushState(player)
end

local function handleConsumablePurchase(player: Player, itemId: string)
	local def = StoreConfig.GetConsumable(itemId)
	if not def then
		fail(player, "Consumable", itemId, "InvalidItem")
		return
	end

	if not DataService.Get(player) then
		fail(player, "Consumable", itemId, "ProfileNotLoaded")
		return
	end

	if not trySpend(player, def.Currency, def.Price) then
		fail(player, "Consumable", itemId, "NotEnoughCurrency")
		return
	end

	if def.Kind == "InstantCoins" then
		EconomyService.AwardCoins(player, def.CoinsGranted, def.Name)
	end

	purchaseResultEvent:FireClient(player, {
		Success = true,
		Category = "Consumable",
		ItemId = itemId,
	})
	notify(player, `Purchased {def.Name}!`, "Success")
	pushState(player)
	EconomyService.PushState(player)
end

local function onRequestPurchase(player: Player, category: unknown, itemId: unknown)
	if typeof(category) ~= "string" or typeof(itemId) ~= "string" then
		return
	end

	if category == "Upgrade" then
		handleUpgradePurchase(player, itemId)
	elseif category == "Boost" then
		handleBoostPurchase(player, itemId)
	elseif category == "Consumable" then
		handleConsumablePurchase(player, itemId)
	else
		fail(player, tostring(category), itemId, "InvalidItem")
	end
end

-- === Lifecycle ================================================================

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character :: Model)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onProfileLoaded(player: Player, _profile: DataService.Profile)
	pushState(player)
	if player.Character then
		applyWalkSpeed(player, player.Character)
	end
end

function StoreService.Init()
	requestPurchaseEvent = Net.GetEvent(Constants.REMOTE_NAMES.Store.RequestPurchase)
	purchaseResultEvent = Net.GetEvent(Constants.REMOTE_NAMES.Store.PurchaseResult)
	stateUpdatedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Store.StateUpdated)

	requestPurchaseEvent.OnServerEvent:Connect(onRequestPurchase)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
		if DataService.Get(player) then
			task.spawn(onProfileLoaded, player, DataService.Get(player) :: DataService.Profile)
		end
	end
end

return StoreService
