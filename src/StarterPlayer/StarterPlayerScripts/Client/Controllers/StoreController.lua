--!strict
-- Thin client glue: wires the Store nav button + remotes to StoreUI. All UI
-- construction lives in StoreUI.lua; all validation/spending lives
-- server-side in StoreService.lua. This controller never grants currency or
-- upgrades itself - it only forwards purchase requests and forwards server
-- pushes into StoreUI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local StoreUI = require(Client.UI.StoreUI)

local StoreController = {}

local function onPurchase(category: string, itemId: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Store.RequestPurchase):FireServer(category, itemId)
end

function StoreController.Init()
	local root = StoreUI.Init({
		OnPurchase = onPurchase,
	})
	root.Parent = Shell.GetScreenGui()

	Shell.RegisterNavButton({
		Id = "NavStore",
		Label = "Store",
		IconText = "🛒",
		Order = 30,
		Panel = root,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Store.StateUpdated).OnClientEvent:Connect(function(state: any)
		StoreUI.SetState(state)
	end)

	-- The server already fires Shared_Notify with a human-readable message for
	-- both success and failure, so this listener is currently unused beyond
	-- keeping the remote wired for future UI-only reactions (e.g. a purchase
	-- flash animation) without needing another round trip.
	Net.GetEvent(Constants.REMOTE_NAMES.Store.PurchaseResult).OnClientEvent:Connect(function(_result: any) end)
end

return StoreController
