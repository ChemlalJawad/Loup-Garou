--!strict
-- Game Pass + Developer Product catalog for the Robux shop. Pure data plus
-- pure-function lookup helpers only (no DataService/Net/MarketplaceService
-- access here) so both server (ShopService, authoritative grants) and client
-- (ShopUI, catalog rendering) can require this safely.
--
-- ============================================================================
-- PUBLISHING CHECKLIST - read this before shipping
-- ============================================================================
-- Every `Id` below is the placeholder `0`. Game Passes and Developer Products
-- can only be created for a *published* place from the Roblox Creator
-- Dashboard, so there is nothing meaningful to put here until this game
-- ships. To go live:
--   1. Publish the place at least once (Creator Dashboard requires a place
--      to exist before you can create passes/products against it).
--   2. In the Creator Dashboard, create one Game Pass per entry in
--      `gamePasses` below (VIP, Double Coins, Double Luck,
--      +50 Inventory Slots) and one Developer Product per entry in
--      `products` below (the 4 Gems packs + 3 Coins packs). Set whatever
--      Robux price you want in the dashboard - prices are NOT configured
--      here, Roblox renders its own native price on the purchase prompt.
--   3. Paste each numeric id the dashboard gives you over the matching `0`
--      below. Search this file for "-- TODO: set real id" to find every
--      spot that needs one (also greppable from the repo root).
--   4. That's it - no other code changes needed. The moment a specific
--      item's `Id` stops being `0`, `ShopConfig.IsTestModeForId` for that
--      item returns false automatically, so its shop card switches from
--      "Coming soon" / "TEST BUY" to a real MarketplaceService prompt with
--      zero further edits. Items you haven't published yet keep working in
--      Studio and keep showing "Coming soon" to real players.
-- ============================================================================
--
-- Because every Id is the same placeholder right now, anything that keys off
-- `Id` (DataService's `OwnedGamePasses` map, `ShopConfig.GetProductById`)
-- will alias all entries together until real, distinct ids are filled in.
-- That's expected at this stage (including in TEST_MODE - see below) and
-- resolves itself the moment real ids are set.

local RunService = game:GetService("RunService")
local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local ShopConfig = {}

-- === Test mode ===============================================================
--
-- Whether to let a developer exercise the full purchase -> grant -> UI flow
-- in Studio without a real MarketplaceService id. This flag is checked
-- ONLY at require-time (server + client each evaluate it once, like every
-- other value in this module) via RunService:IsStudio(), which is a
-- structural guarantee, not a config toggle: IsStudio() is hard-coded false
-- by Roblox in every live, published server a real player can join. There is
-- no live-server code path that can ever observe TEST_MODE = true.
--
-- ShopConfig.TEST_MODE alone is NOT the gate callers should use - always call
-- ShopConfig.IsTestModeForId(id) instead, which ALSO requires the specific
-- pass/product's Id to still be the `0` placeholder. This second condition
-- means that even inside Studio, an item stops being simulated the instant a
-- real id is pasted in (e.g. for QA-ing the real MarketplaceService flow
-- against a test place), and it's what makes it structurally impossible to
-- ever simulate a free grant of a *real*, purchasable product.
ShopConfig.TEST_MODE = RunService:IsStudio()

-- The one function every call site (ShopService, ShopController, ShopUI)
-- should use to decide "is this specific pass/product simulated right now".
-- See the TEST_MODE comment above for why both conditions are required.
function ShopConfig.IsTestModeForId(id: number): boolean
	return ShopConfig.TEST_MODE and id == 0
end

export type CurrencyKey = "Coins" | "Gems"

export type PerkName = "DoubleCoins" | "DoubleLuck"

export type GamePassKey = "VIP" | "DoubleCoins" | "DoubleLuck" | "ExtraInventorySlots"

export type ProductKey =
	"GemsSmall"
	| "GemsMedium"
	| "GemsLarge"
	| "GemsMega"
	| "CoinsSmall"
	| "CoinsMedium"
	| "CoinsLarge"

-- One-time-purchase, permanent-effect Game Pass definition. Effect fields are
-- optional and additive - ShopService applies whichever ones are present
-- instead of switching on `Key`, so adding a new pass never needs a new
-- branch in ShopService.
export type GamePassDefinition = {
	Key: GamePassKey,
	Id: number, -- TODO: set real id from Creator Dashboard
	Name: string,
	Description: string,
	-- Perk flag to set true via DataService.SetPerk on ownership (idempotent -
	-- safe to (re)apply every time ownership is confirmed).
	PerkName: PerkName?,
	-- One-time Coins bonus granted the first time this pass is detected as
	-- owned (guarded by ShopService so rejoining never re-grants it).
	BonusCoins: number?,
	-- One-time permanent inventory slot grant, same one-time guard as above.
	InventorySlotBonus: number?,
}

-- Repeatable Developer Product definition: grants a fixed amount of a single
-- currency every time it's purchased.
export type ProductDefinition = {
	Key: ProductKey,
	Id: number, -- TODO: set real id from Creator Dashboard
	Name: string,
	Description: string,
	Currency: CurrencyKey,
	Amount: number,
}

-- === Game Passes ===========================================================

local gamePasses: { [GamePassKey]: GamePassDefinition } = {
	VIP = {
		Key = "VIP",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "VIP",
		Description = "Exclusive VIP chat tag, a VIP-only hangout area, and a one-time Coins bonus.",
		BonusCoins = 1000,
	},
	DoubleCoins = {
		Key = "DoubleCoins",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Double Coins",
		Description = "Permanently earn 2x Coins from every source in the game.",
		PerkName = "DoubleCoins",
	},
	DoubleLuck = {
		Key = "DoubleLuck",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Double Luck",
		Description = "Permanently improved odds for Rare and better hatches.",
		PerkName = "DoubleLuck",
	},
	ExtraInventorySlots = {
		Key = "ExtraInventorySlots",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "+50 Inventory Slots",
		Description = "Permanently adds 50 slots to your Brainrot inventory.",
		InventorySlotBonus = 50,
	},
}
ShopConfig.GamePasses = gamePasses

-- Stable display order for UI iteration (table iteration order is undefined).
local gamePassOrder: { GamePassKey } = { "VIP", "DoubleCoins", "DoubleLuck", "ExtraInventorySlots" }
ShopConfig.GamePassOrder = gamePassOrder

-- === Developer Products =====================================================

-- Gems packs (premium currency) - standard bulk-discount curve, better Gems-
-- per-Robux at higher tiers. Robux prices themselves aren't set here: they're
-- configured in the Creator Dashboard against each product Id and rendered
-- natively by Roblox's own purchase-confirmation UI.
local products: { [ProductKey]: ProductDefinition } = {
	GemsSmall = {
		Key = "GemsSmall",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Small Gem Pack",
		Description = "A handful of Gems to get started.",
		Currency = Constants.CURRENCY.HARD,
		Amount = 100,
	},
	GemsMedium = {
		Key = "GemsMedium",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Medium Gem Pack",
		Description = "A solid stash of Gems. Better value than Small.",
		Currency = Constants.CURRENCY.HARD,
		Amount = 550,
	},
	GemsLarge = {
		Key = "GemsLarge",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Large Gem Pack",
		Description = "A big pile of Gems for serious hatching sessions.",
		Currency = Constants.CURRENCY.HARD,
		Amount = 1200,
	},
	GemsMega = {
		Key = "GemsMega",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Mega Gem Pack",
		Description = "The best Gems-per-Robux value in the shop.",
		Currency = Constants.CURRENCY.HARD,
		Amount = 2600,
	},

	-- Coins packs (soft currency) - smaller Robux price tiers than Gems since
	-- Coins are earned freely in-game; these exist for players who want to
	-- skip the grind rather than for players who want premium perks.
	CoinsSmall = {
		Key = "CoinsSmall",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Small Coin Pack",
		Description = "A quick top-up of Coins.",
		Currency = Constants.CURRENCY.SOFT,
		Amount = 1000,
	},
	CoinsMedium = {
		Key = "CoinsMedium",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Medium Coin Pack",
		Description = "A generous stack of Coins. Better value than Small.",
		Currency = Constants.CURRENCY.SOFT,
		Amount = 5500,
	},
	CoinsLarge = {
		Key = "CoinsLarge",
		Id = 0, -- TODO: set real id from Creator Dashboard
		Name = "Large Coin Pack",
		Description = "The best Coins-per-Robux value in the shop.",
		Currency = Constants.CURRENCY.SOFT,
		Amount = 12000,
	},
}
ShopConfig.Products = products

-- Stable display order for UI iteration: Gems packs first (premium, higher
-- price tier), then Coins packs (soft currency, lower price tier).
local productOrder: { ProductKey } =
	{ "GemsSmall", "GemsMedium", "GemsLarge", "GemsMega", "CoinsSmall", "CoinsMedium", "CoinsLarge" }
ShopConfig.ProductOrder = productOrder

function ShopConfig.GetGamePass(key: string): GamePassDefinition?
	return ShopConfig.GamePasses[key :: GamePassKey]
end

function ShopConfig.GetProduct(key: string): ProductDefinition?
	return ShopConfig.Products[key :: ProductKey]
end

-- Id -> ProductDefinition index for ProcessReceipt, which only ever gives us
-- a numeric ProductId (never the string Key). Built once at require-time.
--
-- Because every placeholder Id is currently `0`, this index can only ever
-- resolve to one entry (first one wins) until real ids are filled in - real
-- purchases can't happen against placeholder ids anyway (MarketplaceService
-- rejects PromptProductPurchase for an invalid id), so this doesn't cause an
-- observable bug today. The loop below still warns about *accidental*
-- duplicate ids once they stop being `0`, as a safety net for the day this
-- file gets real numbers.
local productsById: { [number]: ProductDefinition } = {}
do
	local seenNonZeroIds: { [number]: ProductKey } = {}
	for _, key in ShopConfig.ProductOrder do
		local product = ShopConfig.Products[key]
		if productsById[product.Id] == nil then
			productsById[product.Id] = product
		end
		if product.Id ~= 0 then
			local existingKey = seenNonZeroIds[product.Id]
			if existingKey and existingKey ~= key then
				warn(`[ShopConfig] duplicate Developer Product Id {product.Id} used by both "{existingKey}" and "{key}"`)
			else
				seenNonZeroIds[product.Id] = key
			end
		end
	end
end

function ShopConfig.GetProductById(id: number): ProductDefinition?
	return productsById[id]
end

return ShopConfig
