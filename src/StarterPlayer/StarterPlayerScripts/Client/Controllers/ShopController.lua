--!strict
-- Thin client glue: wires the Shop nav button + remotes to ShopUI. All UI
-- construction lives in ShopUI.lua; all validation/granting lives
-- server-side in ShopService.lua. This controller never grants currency or
-- perks itself - it only forwards requests and forwards server pushes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local ShopUI = require(Client.UI.ShopUI)

local ShopController = {}

local function onBuyGamePass(passKey: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.PromptGamePass):FireServer(passKey)
end

local function onBuyProduct(productKey: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shop.PromptProduct):FireServer(productKey)
end

function ShopController.Init()
	local shopPanel = ShopUI.Init({
		OnBuyGamePass = onBuyGamePass,
		OnBuyProduct = onBuyProduct,
	})

	-- Panel=shopPanel hands exclusive show/hide of this screen to Shell (only
	-- one registered panel is ever open at once); ShopUI no longer tracks its
	-- own `visible` boolean. Order=40 matches the Shop slot in the nav dock
	-- order documented in docs/EXPANSION_PLAN.md.
	Shell.RegisterNavButton({
		Id = "NavShop",
		Label = "Shop",
		IconText = "💎",
		Panel = shopPanel,
		Order = 40,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Shop.CurrencyUpdated).OnClientEvent:Connect(function(coins: number, gems: number)
		Shell.SetCurrency(Constants.CURRENCY.SOFT, coins)
		Shell.SetCurrency(Constants.CURRENCY.HARD, gems)
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Shop.OwnedPassesUpdated).OnClientEvent:Connect(function(ownedPasses: { [number]: boolean })
		ShopUI.SetOwnedPasses(ownedPasses)
	end)
end

return ShopController
