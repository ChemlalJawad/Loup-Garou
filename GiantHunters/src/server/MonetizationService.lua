--!strict
-- The Robux shop: game passes and developer products (Config.Monetization).
--
-- Kid-friendly by design: nothing sold for Robux makes a hunter stronger by
-- itself (items stay level-locked, Marks bags only buy what your level
-- already allows), no paid random loot, no timers or pop-ups. A purchase
-- prompt only opens when a player presses a button in the shop, and the
-- server checks the request first (a known item, an id that isn't 0, not
-- owned already). Ids of 0 are "not set up": hidden and refused.
--
--   * Passes are checked on join (UserOwnsGamePassAsync, in a pcall, retried,
--     cached) and on PromptGamePassPurchaseFinished, and published as the
--     player attributes "Pass_<Key>" (true / false):
--       DoubleMarks      "MarksMult" = 2 (ProgressService multiplies Marks from play)
--       CommanderPack    the styles with PassKey "CommanderPack" + the "Elite Commander" title
--       SecondTechnique  the second technique slot (ShopService, TechniqueService)
--       ShifterPack      the TitanSkin styles with PassKey "ShifterPack"
--       SeasonPremium    the premium season track (SeasonService)
--   * Products go through ProcessReceipt, which is idempotent: each
--     PurchaseId granted is recorded in the player's profile (DataService
--     "Receipts") and the profile is saved straight away; the purchase is
--     only confirmed (PurchaseGranted) once that save worked. A receipt for
--     a player whose data isn't loaded, or whose save failed, answers
--     NotProcessedYet and Roblox asks again later (never granted twice: a
--     recorded PurchaseId is only saved again).
--       MarksSmall / Medium / Large  Marks (Config.Monetization.MarksBags)
--       ServerXPBoost   x2 XP for everyone in the server for 30 minutes
--                       (stacks; the Workspace attribute "XPBoostUntil",
--                       server time, read by LevelService and the HUD)
--       ChallengeReroll swap one daily challenge (the one picked in the shop)
--       Fireworks       a firework show over the buyer, for everyone
--       single styles   Config.Monetization.Products.Cosmetics[item.ProductKey]
--                       (ShopService.GrantStyle)
--
-- Client requests: Config.Remotes.Monetization ("Buy", key, arg?) and
-- ("BuyCosmetic", itemId).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)
local Broadcast = require(script.Parent.Broadcast)

local MonetizationService = {}

local M = Config.Monetization
local REROLL_FALLBACK_MARKS = 100 -- (if no challenge could be swapped in after all)

type Grant = (player: Player) -> boolean

local remote: RemoteEvent
local passes: { [Player]: { [string]: boolean } } = {}
local nextPrompt: { [Player]: number } = {}
local rerollChoice: { [Player]: string } = {}
local pending: { [string]: boolean } = {} -- PurchaseIds being granted right now
local passKeys: { [number]: string } = {} -- pass id -> key
local grants: { [number]: Grant } = {} -- product id -> what it gives

-- === Passes ==================================================================

local function passId(key: string): number
	return M.GamePasses[key] or 0
end

-- A product's id by its key (0: not set up; the styles are separate).
local function productId(key: string): number
	local id = (M.Products :: any)[key]
	return if type(id) == "number" then id else 0
end

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local owned = passes[player]
	return owned ~= nil and owned[key] == true
end

local function sendState(player: Player)
	if not player.Parent then
		return
	end
	local owned: { [string]: boolean } = {}
	for key in M.GamePasses do
		owned[key] = MonetizationService.OwnsPass(player, key)
	end
	remote:FireClient(player, "State", { Passes = owned })
end

-- Publishes a pass and everything that hangs on it.
local function setPass(player: Player, key: string, owned: boolean)
	local cache = passes[player]
	if not cache then
		return
	end
	cache[key] = owned
	player:SetAttribute(`Pass_{key}`, owned)
	if key == "DoubleMarks" then
		player:SetAttribute("MarksMult", if owned then M.DoubleMarksMultiplier else 1)
	end
	ShopService.Refresh(player) -- (pass styles, the second technique slot)
	ProgressService.Refresh(player) -- (the Elite Commander title)
	sendState(player)
end

local function checkPasses(player: Player)
	for key, id in M.GamePasses do
		if id ~= 0 then
			for attempt = 1, 3 do
				local ok, owned = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
				end)
				if ok then
					if owned == true and player.Parent then
						setPass(player, key, true)
					end
					break
				end
				warn(`[MonetizationService] pass check {key} for {player.Name} failed (try {attempt}): {owned}`)
				task.wait(attempt * 2)
			end
		end
	end
end

-- === Product grants ==========================================================

local function marksBag(key: string): Grant
	return function(player: Player): boolean
		local amount = M.MarksBags[key] or 0
		if not ProgressService.GrantMarks(player, amount) then
			return false
		end
		Broadcast.Feed(`+{amount} Marks. Thank you for supporting the game!`, "Gold", player)
		return true
	end
end

local function xpBoost(player: Player): boolean
	local now = Workspace:GetServerTimeNow()
	local current = Workspace:GetAttribute("XPBoostUntil")
	local from = if type(current) == "number" and current > now then current else now
	Workspace:SetAttribute("XPBoostUntil", from + M.XPBoost.Duration)
	Broadcast.Feed(`Thanks {player.DisplayName} for the XP boost! Double XP for everyone!`, "Gold")
	return true
end

local function reroll(player: Player): boolean
	if ProgressService.Reroll(player, rerollChoice[player]) then
		rerollChoice[player] = nil
		return true
	end
	-- (Nothing left to swap in: Marks instead, so the purchase is never lost.)
	if ProgressService.GrantMarks(player, REROLL_FALLBACK_MARKS) then
		Broadcast.Feed(`No new challenge to swap in: +{REROLL_FALLBACK_MARKS} Marks instead`, "Good", player)
		return true
	end
	return false
end

local function fireworks(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart")
		then root.Position + Vector3.new(0, M.Fireworks.Height, 0)
		else Vector3.new(0, M.Fireworks.Height + 20, 0) -- (over the plaza)
	remote:FireAllClients("Fireworks", position, player.DisplayName)
	Broadcast.Feed(`{player.DisplayName} lit up the sky with fireworks!`, "Gold")
	return true
end

local function style(itemId: string): Grant
	return function(player: Player): boolean
		return ShopService.GrantStyle(player, itemId)
	end
end

local function styleItem(id: string): { [string]: any }?
	local items = (Config :: any).CosmeticItems
	local item = if type(items) == "table" then items[id] else nil
	return if type(item) == "table" then item else nil
end

-- A Robux style's product id (0: not for sale).
local function styleProduct(id: string): number
	local item = styleItem(id)
	if not item or item.Source ~= "Robux" then
		return 0
	end
	local key = if type(item.ProductKey) == "string" then item.ProductKey else id
	return M.Products.Cosmetics[key] or 0
end

local function buildGrants()
	local byKey: { [string]: Grant } = {
		MarksSmall = marksBag("MarksSmall"),
		MarksMedium = marksBag("MarksMedium"),
		MarksLarge = marksBag("MarksLarge"),
		ServerXPBoost = xpBoost,
		ChallengeReroll = reroll,
		Fireworks = fireworks,
	}
	for key, grant in byKey do
		local id = productId(key)
		if id ~= 0 then
			grants[id] = grant
		end
	end
	local items = (Config :: any).CosmeticItems
	if type(items) == "table" then
		for id in items do
			if type(id) == "string" then
				local product = styleProduct(id)
				if product ~= 0 then
					grants[product] = style(id)
				end
			end
		end
	end
	for key, id in M.GamePasses do
		if id ~= 0 then
			passKeys[id] = key
		end
	end
end

-- === Receipts ================================================================

-- Saves after a grant: confirmed only once the save worked (in Studio
-- without a DataStore there's nothing to save, so test purchases go through).
local function confirm(player: Player): Enum.ProductPurchaseDecision
	if DataService.Saving() then
		return if DataService.SaveNow(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or player:GetAttribute("DataLoaded") ~= true or not DataService.Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if pending[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	pending[purchaseId] = true
	local decision = Enum.ProductPurchaseDecision.NotProcessedYet
	if DataService.HasReceipt(player, purchaseId) then
		decision = confirm(player) -- (granted before; only the save is left)
	else
		local grant = grants[receipt.ProductId]
		if grant then
			local ok, granted = pcall(grant, player)
			if ok and granted then
				DataService.RecordReceipt(player, purchaseId)
				decision = confirm(player)
				remote:FireClient(player, "Result", true, "Thank you! Your purchase is in.")
			elseif not ok then
				warn(`[MonetizationService] granting product {receipt.ProductId} failed: {granted}`)
			end
		else
			warn(`[MonetizationService] unknown product id {receipt.ProductId}: is it in Config.Monetization?`)
		end
	end
	pending[purchaseId] = nil
	return decision
end

-- === Requests ================================================================

local function result(player: Player, ok: boolean, message: string)
	remote:FireClient(player, "Result", ok, message)
end

local function prompt(player: Player, kind: string, id: number)
	local ok, err = pcall(function()
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then
		warn(`[MonetizationService] prompt failed: {err}`)
		result(player, false, "The shop isn't available right now")
	end
end

local function onRequest(player: Player, action: unknown, a: unknown, b: unknown)
	local now = os.clock()
	if now < (nextPrompt[player] or 0) then
		return
	end
	nextPrompt[player] = now + M.PromptCooldown
	if action == "Sync" then
		sendState(player)
		return
	end
	if action == "Buy" and type(a) == "string" then
		local id = passId(a)
		if id ~= 0 then
			if MonetizationService.OwnsPass(player, a) then
				result(player, false, "You already have this pass")
			else
				prompt(player, "Pass", id)
			end
			return
		end
		local product = productId(a)
		if product == 0 or not grants[product] then
			return -- (not set up: refused)
		end
		if a == "ChallengeReroll" then
			if player:GetAttribute("DataLoaded") ~= true then
				result(player, false, "Still loading your progress...")
				return
			end
			if type(b) == "string" and #b <= 40 then
				rerollChoice[player] = b
			end
		end
		prompt(player, "Product", product)
	elseif action == "BuyCosmetic" and type(a) == "string" and #a <= 60 then
		local product = styleProduct(a)
		if product == 0 or not grants[product] then
			return
		end
		if ShopService.OwnsStyle(player, a) then
			result(player, false, "You already have this style")
			return
		end
		prompt(player, "Product", product)
	end
end

-- === Init ====================================================================

local function onPlayerAdded(player: Player)
	passes[player] = {}
	for key in M.GamePasses do
		player:SetAttribute(`Pass_{key}`, false)
	end
	player:SetAttribute("MarksMult", 1)
	task.spawn(checkPasses, player)
end

function MonetizationService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Monetization) :: RemoteEvent
	buildGrants()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		passes[player] = nil
		nextPrompt[player] = nil
		rerollChoice[player] = nil
	end)
	remote.OnServerEvent:Connect(onRequest)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, purchased: boolean)
		local key = passKeys[id]
		if purchased and key and passes[player] then
			setPass(player, key, true)
			Broadcast.Feed(`Thanks {player.DisplayName} for supporting the game!`, "Gold")
			result(player, true, "Thank you! Your pass is active.")
		end
	end)
	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
