--!strict
-- Server-authoritative Robux shop: prompts Game Pass / Developer Product
-- purchases, processes receipts, and applies the resulting effects via
-- DataService. Never trusts a client-sent price or grant amount - every
-- grant here is looked up from ShopConfig by a server-validated key/id.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)

local ShopService = {}

-- Minimal shape of the table Roblox passes into MarketplaceService.ProcessReceipt.
-- (Not a full Roblox type - just the fields this module actually reads.)
type ReceiptInfo = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	[string]: any,
}

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function pushCurrency(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.CurrencyUpdated):FireClient(player, profile.Coins, profile.Gems)
end

local function pushOwnedPasses(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.OwnedPassesUpdated):FireClient(player, profile.OwnedGamePasses)
end

-- Per-player mutex + "run again" flag around syncAllGamePasses. Ownership
-- checks yield on a network call (UserOwnsGamePassAsync), so without this a
-- join-time sync and a purchase-finished sync could interleave and both
-- observe "not owned yet", double-granting a one-time effect (e.g. +50
-- inventory slots twice). See syncAllGamePasses below.
local gamePassSyncLocked: { [Player]: boolean } = {}
local gamePassSyncPending: { [Player]: boolean } = {}

-- Applies the gameplay effect of an owned Game Pass. Perk flags are
-- idempotent and reapplied every time ownership is (re)confirmed; one-time
-- grants (bonus coins, inventory slots) only fire when `isNewlyDetected` is
-- true, so rejoining or re-checking ownership never stacks them.
local function applyGamePassEffect(player: Player, passConfig: ShopConfig.GamePassDefinition, isNewlyDetected: boolean)
	if passConfig.PerkName then
		DataService.SetPerk(player, passConfig.PerkName, true)
	end

	if not isNewlyDetected then
		return
	end

	if passConfig.BonusCoins then
		DataService.AddCoins(player, passConfig.BonusCoins)
	end
	if passConfig.InventorySlotBonus then
		DataService.AddInventorySlots(player, passConfig.InventorySlotBonus)
	end
end

-- Checks live ownership of a single Game Pass and applies its effect if
-- owned. Safe to call repeatedly (e.g. every ProfileLoaded / purchase
-- finished) - one-time grants are guarded via DataService.HasGamePass.
local function detectAndApplyGamePass(player: Player, passConfig: ShopConfig.GamePassDefinition): boolean
	if not player.Parent then
		return false
	end

	local alreadyOwnedInProfile = DataService.HasGamePass(player, passConfig.Id)

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passConfig.Id)
	end)

	if not ok then
		warn(`[ShopService] UserOwnsGamePassAsync failed for {player.Name} / pass "{passConfig.Key}":`, owns)
		return false
	end

	if not owns then
		return false
	end

	local isNewlyDetected = not alreadyOwnedInProfile
	if isNewlyDetected then
		DataService.SetGamePassOwned(player, passConfig.Id, true)
	end

	applyGamePassEffect(player, passConfig, isNewlyDetected)
	return isNewlyDetected
end

-- Re-checks ownership of every configured Game Pass for a player and applies
-- effects for any newly-owned ones. Serialized per player (see the lock
-- comment above) so overlapping calls never race each other.
local function syncAllGamePasses(player: Player)
	if gamePassSyncLocked[player] then
		gamePassSyncPending[player] = true
		return
	end

	gamePassSyncLocked[player] = true
	local anyNewlyGranted = false

	repeat
		gamePassSyncPending[player] = nil
		for _, key in ShopConfig.GamePassOrder do
			local passConfig = ShopConfig.GamePasses[key]
			if detectAndApplyGamePass(player, passConfig) then
				anyNewlyGranted = true
			end
		end
	until not gamePassSyncPending[player]

	gamePassSyncLocked[player] = nil

	if anyNewlyGranted and player.Parent then
		pushOwnedPasses(player)
		pushCurrency(player)
	end
end

local function onPromptGamePass(player: Player, passKey: unknown)
	if typeof(passKey) ~= "string" then
		return
	end

	local passConfig = ShopConfig.GetGamePass(passKey)
	if not passConfig then
		warn(`[ShopService] onPromptGamePass: unknown pass key "{tostring(passKey)}"`)
		return
	end

	MarketplaceService:PromptGamePassPurchase(player, passConfig.Id)
end

local function onPromptProduct(player: Player, productKey: unknown)
	if typeof(productKey) ~= "string" then
		return
	end

	local productConfig = ShopConfig.GetProduct(productKey)
	if not productConfig then
		warn(`[ShopService] onPromptProduct: unknown product key "{tostring(productKey)}"`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, productConfig.Id)
end

local function onGamePassPurchaseFinished(player: Player, _gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or not player.Parent then
		return
	end

	-- Re-check every pass rather than trying to map `_gamePassId` back to a
	-- single ShopConfig entry: while every Id is still the placeholder `0`,
	-- that mapping would be ambiguous. A full resync is cheap (one Async call
	-- per pass) and correct in both the placeholder and real-id cases.
	syncAllGamePasses(player)
	notify(player, "Purchase complete - thank you!", "Success")
end

-- The standard safe ProcessReceipt pattern: look up the product, grant it via
-- DataService, and only return PurchaseGranted once the grant has actually
-- happened. Every other path returns NotProcessedYet so Roblox retries the
-- receipt later (for up to 3 days) instead of us silently losing it.
--
-- NOTE: the real MarketplaceService API only exposes two
-- Enum.ProductPurchaseDecision values - NotProcessedYet and PurchaseGranted.
-- There is no "PurchasePending" value; NotProcessedYet is the correct signal
-- for "the player's data isn't loaded yet, try again" as well as for "an
-- internal error happened, try again" - both are just "not processed yet".
local function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player isn't in this server right now. Ask for a retry rather than
		-- lose the receipt - Roblox will call this again later.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.Get(player)
	if not profile then
		-- Profile hasn't finished loading yet - retry later rather than risk
		-- granting into a profile that's about to be overwritten by a load.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productConfig = ShopConfig.GetProductById(receiptInfo.ProductId)
	if not productConfig then
		warn(`[ShopService] ProcessReceipt: unknown ProductId {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local grantOk = pcall(function()
		if productConfig.Currency == Constants.CURRENCY.HARD then
			DataService.AddGems(player, productConfig.Amount)
		else
			DataService.AddCoins(player, productConfig.Amount)
		end
	end)

	if not grantOk then
		warn(`[ShopService] ProcessReceipt: failed to grant "{productConfig.Key}" to {player.Name}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	pushCurrency(player)
	notify(player, `Purchased {productConfig.Name}!`, "Success")

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onProfileLoaded(player: Player, _profile: DataService.Profile)
	syncAllGamePasses(player)
	-- Always push initial state on load, even if nothing was newly granted,
	-- so the client's currency pill and owned-pass set are populated from
	-- whatever the player already had saved.
	pushCurrency(player)
	pushOwnedPasses(player)
end

local function onPlayerRemoving(player: Player)
	gamePassSyncLocked[player] = nil
	gamePassSyncPending[player] = nil
end

function ShopService.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.PromptGamePass).OnServerEvent:Connect(onPromptGamePass)
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.PromptProduct).OnServerEvent:Connect(onPromptProduct)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassPurchaseFinished)
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Defensive: if a player's profile already finished loading before this
	-- Init() ran (e.g. it loaded synchronously during DataService.Init(),
	-- which happens earlier in Main.server.lua), we'd have missed that
	-- ProfileLoaded firing. Catch up on anyone already loaded now.
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end
end

return ShopService
