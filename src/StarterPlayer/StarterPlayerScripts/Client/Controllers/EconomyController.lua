--!strict
-- Thin glue for the idle-income/rebirth surfaces: inits RebirthUI and
-- RewardPopup (both self-contained - RebirthUI registers its own nav button
-- and fires its own RequestRebirth remote) and forwards the three Economy
-- remotes into them. Main.client.lua already wires Economy.StateUpdated into
-- Shell.SetCurrency/SetLevel/SetMultiplier directly, so this controller does
-- NOT duplicate that - it only feeds the extra surfaces Main.client.lua
-- doesn't know about.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local RebirthUI = require(Client.UI.RebirthUI)
local RewardPopup = require(Client.UI.RewardPopup)

local EconomyController = {}

function EconomyController.Init()
	RewardPopup.Init()
	RebirthUI.Init()

	Net.GetEvent(Constants.REMOTE_NAMES.Economy.StateUpdated).OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			RebirthUI.SetState(state)
		end
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Economy.RebirthResult).OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		RebirthUI.HandleRebirthResult(result)
		if not result.Success and result.Reason then
			Shell.Notify("Rebirth unavailable right now.", "Warning")
		end
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Economy.RewardPopup).OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			RewardPopup.Show(payload)
		end
	end)
end

return EconomyController
