--!strict
-- Pure data + pure helpers for the in-game-currency Store (Coins/Gems only,
-- never Robux). Read by both StoreService (server, authoritative pricing) and
-- StoreUI (client, display) so the price shown to a player can never drift
-- from the price the server actually charges: both sides call the exact same
-- `PriceForTier` function defined here.
--
-- Three categories:
--   A. Upgrades   - tiered, permanent, stored in profile.Upgrades[id] = tier
--   B. Boosts     - timed, consumable, stack by extending duration
--   C. Consumables - one-shot instant-effect purchases
--
-- This module does not require DataService/EconomyService: it is pure data
-- that both client and server can safely require.

local StoreConfig = {}

export type CurrencyKind = "Coins" | "Gems"

-- === Upgrades ================================================================

export type UpgradeId = string

export type UpgradeDefinition = {
	Id: UpgradeId,
	Name: string,
	Description: string,
	Currency: CurrencyKind,
	MaxTier: number,
	BasePrice: number,
	PriceMultiplier: number,
	-- EffectPerTier's meaning is documented per-upgrade below; StoreService
	-- interprets it by Id since each upgrade applies a different kind of
	-- effect (slot count, speed, multiplier, additive bonus).
	EffectPerTier: number,
	-- Price to advance from (tier - 1) -> tier, i.e. PriceForTier(1) is the
	-- cost of the first purchase. Pure function of BasePrice/PriceMultiplier
	-- so there is exactly one source of truth for price math.
	PriceForTier: (tier: number) -> number,
}

-- price(tier) = BasePrice * PriceMultiplier ^ (tier - 1), rounded to a whole
-- number since both currencies are integer amounts.
local function makeTierPricer(basePrice: number, multiplier: number): (number) -> number
	return function(tier: number): number
		return math.floor(basePrice * (multiplier ^ (tier - 1)) + 0.5)
	end
end

local upgrades: { [UpgradeId]: UpgradeDefinition } = {}

upgrades.InventorySlots = {
	Id = "InventorySlots",
	Name = "Inventory Slots",
	Description = "+25 Brainrot inventory slots per tier.",
	Currency = "Coins",
	MaxTier = 8,
	BasePrice = 1000,
	PriceMultiplier = 1.6,
	EffectPerTier = 25, -- slots granted per tier via DataService.AddInventorySlots
	PriceForTier = makeTierPricer(1000, 1.6),
} :: UpgradeDefinition

upgrades.LuckBoost = {
	Id = "LuckBoost",
	Name = "Luck Boost",
	Description = "Permanently improves your odds of hatching rare Brainrots.",
	Currency = "Gems",
	MaxTier = 5,
	BasePrice = 50,
	PriceMultiplier = 1.8,
	EffectPerTier = 0.01, -- +1% additive luck per tier (read via StoreService.GetLuckBonus)
	PriceForTier = makeTierPricer(50, 1.8),
} :: UpgradeDefinition

upgrades.IdleIncome = {
	Id = "IdleIncome",
	Name = "Idle Income",
	Description = "Permanently increases the Coins your equipped Brainrot earns while idle.",
	Currency = "Coins",
	MaxTier = 10,
	BasePrice = 750,
	PriceMultiplier = 1.55,
	EffectPerTier = 0.08, -- +8% multiplicative per tier (total = 1 + tier * 0.08)
	PriceForTier = makeTierPricer(750, 1.55),
} :: UpgradeDefinition

upgrades.WalkSpeed = {
	Id = "WalkSpeed",
	Name = "Walk Speed",
	Description = "+1 stud/s movement speed in the hub.",
	Currency = "Coins",
	MaxTier = 5,
	BasePrice = 400,
	PriceMultiplier = 1.5,
	EffectPerTier = 1, -- +1 studs/s per tier, applied to Humanoid.WalkSpeed
	PriceForTier = makeTierPricer(400, 1.5),
} :: UpgradeDefinition

StoreConfig.Upgrades = upgrades
StoreConfig.UpgradeOrder = { "InventorySlots", "IdleIncome", "WalkSpeed", "LuckBoost" }

function StoreConfig.GetUpgrade(id: string): UpgradeDefinition?
	return upgrades[id]
end

-- Returns nil (not 0) for an out-of-range tier so callers can distinguish
-- "free"/tier-0 from "invalid tier".
function StoreConfig.PriceForUpgradeTier(id: string, tier: number): number?
	local def = upgrades[id]
	if not def or tier < 1 or tier > def.MaxTier then
		return nil
	end
	return def.PriceForTier(tier)
end

-- === Boosts ==================================================================

-- Family names are the same strings as EconomyService.BOOST_COINS_2X /
-- BOOST_XP_2X / BOOST_LUCK_2X, but this module does not require
-- EconomyService (it's a ServerScriptService module the client can't see) -
-- StoreService maps Family -> the real EconomyService constant itself so
-- there is no risk of a typo'd string silently failing to match.
export type BoostFamily = "Coins2x" | "XP2x" | "Luck2x"

export type BoostId = string

export type BoostDefinition = {
	Id: BoostId,
	Family: BoostFamily,
	Name: string,
	Description: string,
	DurationSeconds: number,
	Currency: CurrencyKind,
	Price: number,
}

local boosts: { [BoostId]: BoostDefinition } = {}

local function addBoost(def: BoostDefinition)
	boosts[def.Id] = def
end

addBoost({
	Id = "Coins2x_15m_Coins",
	Family = "Coins2x",
	Name = "2x Coins - 15 min",
	Description = "Double all Coins earned for 15 minutes.",
	DurationSeconds = 15 * 60,
	Currency = "Coins",
	Price = 800,
})
addBoost({
	Id = "Coins2x_15m_Gems",
	Family = "Coins2x",
	Name = "2x Coins - 15 min",
	Description = "Double all Coins earned for 15 minutes.",
	DurationSeconds = 15 * 60,
	Currency = "Gems",
	Price = 15,
})
addBoost({
	Id = "Coins2x_1h_Coins",
	Family = "Coins2x",
	Name = "2x Coins - 1 hour",
	Description = "Double all Coins earned for 1 hour.",
	DurationSeconds = 60 * 60,
	Currency = "Coins",
	Price = 2800,
})
addBoost({
	Id = "Coins2x_1h_Gems",
	Family = "Coins2x",
	Name = "2x Coins - 1 hour",
	Description = "Double all Coins earned for 1 hour.",
	DurationSeconds = 60 * 60,
	Currency = "Gems",
	Price = 45,
})

addBoost({
	Id = "XP2x_15m_Coins",
	Family = "XP2x",
	Name = "2x XP - 15 min",
	Description = "Double all XP earned for 15 minutes.",
	DurationSeconds = 15 * 60,
	Currency = "Coins",
	Price = 700,
})
addBoost({
	Id = "XP2x_15m_Gems",
	Family = "XP2x",
	Name = "2x XP - 15 min",
	Description = "Double all XP earned for 15 minutes.",
	DurationSeconds = 15 * 60,
	Currency = "Gems",
	Price = 12,
})
addBoost({
	Id = "XP2x_1h_Coins",
	Family = "XP2x",
	Name = "2x XP - 1 hour",
	Description = "Double all XP earned for 1 hour.",
	DurationSeconds = 60 * 60,
	Currency = "Coins",
	Price = 2400,
})
addBoost({
	Id = "XP2x_1h_Gems",
	Family = "XP2x",
	Name = "2x XP - 1 hour",
	Description = "Double all XP earned for 1 hour.",
	DurationSeconds = 60 * 60,
	Currency = "Gems",
	Price = 38,
})

-- Luck2x is deliberately Gems-only: it's the strongest boost in the game, so
-- it stays a premium sink rather than something farmed with Coins.
addBoost({
	Id = "Luck2x_15m_Gems",
	Family = "Luck2x",
	Name = "2x Luck - 15 min",
	Description = "Double your odds of hatching rare Brainrots for 15 minutes.",
	DurationSeconds = 15 * 60,
	Currency = "Gems",
	Price = 60,
})
addBoost({
	Id = "Luck2x_1h_Gems",
	Family = "Luck2x",
	Name = "2x Luck - 1 hour",
	Description = "Double your odds of hatching rare Brainrots for 1 hour.",
	DurationSeconds = 60 * 60,
	Currency = "Gems",
	Price = 200,
})

StoreConfig.Boosts = boosts
StoreConfig.BoostOrder = {
	"Coins2x_15m_Coins",
	"Coins2x_15m_Gems",
	"Coins2x_1h_Coins",
	"Coins2x_1h_Gems",
	"XP2x_15m_Coins",
	"XP2x_15m_Gems",
	"XP2x_1h_Coins",
	"XP2x_1h_Gems",
	"Luck2x_15m_Gems",
	"Luck2x_1h_Gems",
}

function StoreConfig.GetBoost(id: string): BoostDefinition?
	return boosts[id]
end

-- === Consumables =============================================================

export type ConsumableId = string

export type ConsumableKind = "InstantCoins"

export type ConsumableDefinition = {
	Id: ConsumableId,
	Kind: ConsumableKind,
	Name: string,
	Description: string,
	Currency: CurrencyKind,
	Price: number,
	CoinsGranted: number,
}

local consumables: { [ConsumableId]: ConsumableDefinition } = {}

consumables.InstantCoinsSmall = {
	Id = "InstantCoinsSmall",
	Kind = "InstantCoins",
	Name = "Coin Pouch",
	Description = "Instantly exchange Gems for 10,000 Coins.",
	Currency = "Gems",
	Price = 20,
	CoinsGranted = 10000,
} :: ConsumableDefinition

consumables.InstantCoinsLarge = {
	Id = "InstantCoinsLarge",
	Kind = "InstantCoins",
	Name = "Coin Chest",
	Description = "Instantly exchange Gems for 50,000 Coins.",
	Currency = "Gems",
	Price = 80,
	CoinsGranted = 50000,
} :: ConsumableDefinition

StoreConfig.Consumables = consumables
StoreConfig.ConsumableOrder = { "InstantCoinsSmall", "InstantCoinsLarge" }

function StoreConfig.GetConsumable(id: string): ConsumableDefinition?
	return consumables[id]
end

return StoreConfig
