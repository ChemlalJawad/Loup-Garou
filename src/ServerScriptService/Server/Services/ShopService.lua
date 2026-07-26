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
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

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

-- Idempotency bookkeeping for ProcessReceipt --------------------------------
--
-- Roblox can legitimately call ProcessReceipt more than once for the same
-- PurchaseId (e.g. our server returned NotProcessedYet or crashed before
-- returning at all, so Roblox retries). Re-running the grant on a retry
-- would double-pay the player, so we record processed PurchaseIds in the
-- player's profile and no-op (still returning PurchaseGranted) on a repeat.
--
-- There's no dedicated Profile field for this (DataService.lua is owned by
-- another system - see docs/EXPANSION_PLAN.md), so this stores an extra key
-- on the profile table directly via DataService.Mutate rather than adding
-- one. DataService's reconcile() only ever *adds* missing keys from
-- defaultProfile() into a loaded save, it never strips unknown ones, so this
-- key round-trips through save/load fine. The list is capped at
-- PROCESSED_PURCHASE_HISTORY_LIMIT entries so it can't grow the profile
-- forever over a long play history.
local PROCESSED_PURCHASE_HISTORY_LIMIT = 50

local function hasProcessedPurchase(profile: DataService.Profile, purchaseId: string): boolean
	local processed = (profile :: any).ShopProcessedPurchaseIds
	if type(processed) ~= "table" then
		return false
	end
	for _, id in processed :: { string } do
		if id == purchaseId then
			return true
		end
	end
	return false
end

local function markPurchaseProcessed(player: Player, purchaseId: string)
	DataService.Mutate(player, function(profile)
		local anyProfile = profile :: any
		local processed = anyProfile.ShopProcessedPurchaseIds
		if type(processed) ~= "table" then
			processed = {}
			anyProfile.ShopProcessedPurchaseIds = processed
		end
		table.insert(processed, purchaseId)
		local overflow = #processed - PROCESSED_PURCHASE_HISTORY_LIMIT
		for _ = 1, overflow do
			table.remove(processed, 1)
		end
	end)
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

	-- Push the shared Economy HUD (coins/gems/inventory-slot readouts) right
	-- away rather than waiting for the next throttled ProfileChanged tick, so
	-- a purchase feels instant.
	EconomyService.PushState(player)
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
-- comment above) so overlapping calls never race each other. Does NOT push
-- Currency/OwnedPasses updates itself - callers push explicitly afterward,
-- so there's exactly one push per call site regardless of what changed.
local function syncAllGamePasses(player: Player)
	if gamePassSyncLocked[player] then
		gamePassSyncPending[player] = true
		return
	end

	gamePassSyncLocked[player] = true

	repeat
		gamePassSyncPending[player] = nil
		for _, key in ShopConfig.GamePassOrder do
			local passConfig = ShopConfig.GamePasses[key]
			detectAndApplyGamePass(player, passConfig)
		end
	until not gamePassSyncPending[player]

	gamePassSyncLocked[player] = nil
end

-- Test-mode purchase simulation ----------------------------------------------
--
-- ShopConfig.IsTestModeForId(id) is only ever true in Studio AND only for an
-- item whose Id is still the `0` placeholder (see ShopConfig.lua for the
-- full guard rationale). When it's true we skip MarketplaceService entirely
-- - there's no real product to prompt against yet - and grant the benefit
-- directly through the exact same DataService/EconomyService calls a real
-- purchase would use, then push the same result remotes a real purchase
-- pushes, so a developer pressing Play can verify the whole
-- purchase -> grant -> UI flow before the game is ever published.
local function simulateGamePassPurchase(player: Player, passConfig: ShopConfig.GamePassDefinition)
	local alreadyOwned = DataService.HasGamePass(player, passConfig.Id)
	if not alreadyOwned then
		DataService.SetGamePassOwned(player, passConfig.Id, true)
	end
	applyGamePassEffect(player, passConfig, not alreadyOwned)

	pushOwnedPasses(player)
	pushCurrency(player)
	notify(player, `TEST MODE: granted "{passConfig.Name}"`, "Success")
end

local function simulateProductPurchase(player: Player, productConfig: ShopConfig.ProductDefinition)
	local grantOk = pcall(function()
		if productConfig.Currency == Constants.CURRENCY.HARD then
			DataService.AddGems(player, productConfig.Amount)
		else
			DataService.AddCoins(player, productConfig.Amount)
		end
	end)
	if not grantOk then
		warn(`[ShopService] simulateProductPurchase: failed to grant "{productConfig.Key}" to {player.Name}`)
		return
	end

	EconomyService.PushState(player)
	pushCurrency(player)
	notify(player, `TEST MODE: granted {productConfig.Amount} {productConfig.Currency} ({productConfig.Name})`, "Success")
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

	if ShopConfig.IsTestModeForId(passConfig.Id) then
		simulateGamePassPurchase(player, passConfig)
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

	if ShopConfig.IsTestModeForId(productConfig.Id) then
		simulateProductPurchase(player, productConfig)
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
	if not player.Parent then
		return
	end
	pushOwnedPasses(player)
	pushCurrency(player)
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

	-- Idempotency: this exact PurchaseId was already granted (see the
	-- hasProcessedPurchase/markPurchaseProcessed comment above). No-op as a
	-- granted purchase rather than granting a second time.
	if hasProcessedPurchase(profile, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
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

	-- Only mark the receipt processed AFTER the grant has actually succeeded -
	-- if we marked it first and the grant then failed, a legitimate retry
	-- would be swallowed as a false-positive no-op.
	markPurchaseProcessed(player, receiptInfo.PurchaseId)

	EconomyService.PushState(player)
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
