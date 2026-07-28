--!strict
-- Thin client glue for both Daily Rewards and Codes: wires their nav buttons
-- + remotes to DailyUI/CodesUI. One controller drives both UIs deliberately
-- (they're the same "retention" system and share no state, but keeping them
-- as one file-set matches how they're owned). All instance construction
-- lives in the UI modules; this controller only forwards requests and server
-- pushes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local DailyUI = require(Client.UI.DailyUI)
local CodesUI = require(Client.UI.CodesUI)

local DailyController = {}

local function onClaimReward()
	Net.GetEvent(Constants.REMOTE_NAMES.Daily.ClaimReward):FireServer()
end

local function onRedeemCode(code: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Codes.Redeem):FireServer(code)
end

function DailyController.Init()
	DailyUI.Init({ OnClaim = onClaimReward })
	CodesUI.Init({ OnRedeem = onRedeemCode })

	Shell.RegisterNavButton({
		Id = "NavDaily",
		Label = "Daily",
		IconText = "🎁",
		Order = 60,
		Panel = DailyUI.Root,
		OnClick = function() end,
	})

	Shell.RegisterNavButton({
		Id = "NavCodes",
		Label = "Codes",
		IconText = "🎟️",
		Order = 70,
		Panel = CodesUI.Root,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Daily.StateUpdated).OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		DailyUI.SetState(state)
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Daily.ClaimResult).OnClientEvent:Connect(function(result)
		-- Failures and successes are both toasted globally by the server
		-- (Shared_Notify); the next StateUpdated push refreshes the cards. No
		-- extra client-side handling needed here beyond keeping the listener
		-- alive for future use (e.g. a claim animation).
		if type(result) ~= "table" then
			return
		end
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Codes.RedeemResult).OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		CodesUI.ShowResult(result)
	end)
end

return DailyController
