--!strict
-- Thin client glue: wires the Eggs nav button + remotes to EggUI. All UI
-- construction lives in EggUI.lua; all rolling/validation/economy lives
-- server-side in EggService.lua. This controller never rolls rarity, never
-- computes a sell refund, and never decides odds - it only forwards intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local EggUI = require(Client.UI.EggUI)

local EggController = {}

local function onRequestHatch(eggId: string, hatchCount: number)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.RequestHatch):FireServer(eggId, hatchCount)
end

local function onEquipPet(uid: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.EquipPet):FireServer(uid)
end

local function onSellBrainrot(uid: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SellBrainrot):FireServer(uid)
end

local function onSellDuplicates(maxRarity: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SellDuplicates):FireServer({ MaxRarity = maxRarity })
end

local function onMergeBrainrots(brainrotId: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.MergeBrainrots):FireServer(brainrotId)
end

local function onSetAutoHatch(enabled: boolean, eggId: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Egg.SetAutoHatch):FireServer(enabled, eggId)
end

function EggController.Init()
	local panelRoot = EggUI.Init({
		OnRequestHatch = onRequestHatch,
		OnEquipPet = onEquipPet,
		OnSellBrainrot = onSellBrainrot,
		OnSellDuplicates = onSellDuplicates,
		OnMergeBrainrots = onMergeBrainrots,
		OnSetAutoHatch = onSetAutoHatch,
	})

	Shell.RegisterNavButton({
		Id = "NavEggs",
		Label = "Eggs",
		IconText = "🥚",
		Order = 10,
		Panel = panelRoot,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Egg.HatchResult).OnClientEvent:Connect(function(payload)
		EggUI.ShowHatchReveal(payload)
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Egg.InventoryUpdated).OnClientEvent:Connect(function(owned, equippedUid)
		EggUI.SetInventory(owned, equippedUid)
	end)
end

return EggController
