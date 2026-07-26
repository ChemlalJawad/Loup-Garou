--!strict
-- Thin client glue: wires the Eggs nav button + remotes to EggUI. All UI
-- construction lives in EggUI.lua; all rolling/validation lives server-side
-- in EggService.lua. This controller never rolls rarity itself.

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

function EggController.Init()
	EggUI.Init({
		OnRequestHatch = onRequestHatch,
		OnEquipPet = onEquipPet,
	})

	Shell.RegisterNavButton({
		Id = "NavEggs",
		Label = "Eggs",
		IconText = "🥚",
		OnClick = function()
			EggUI.Toggle()
		end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Egg.HatchResult).OnClientEvent:Connect(function(payload)
		EggUI.ShowHatchReveal(payload)
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Egg.InventoryUpdated).OnClientEvent:Connect(function(owned, equippedUid)
		EggUI.SetInventory(owned, equippedUid)
	end)
end

return EggController
