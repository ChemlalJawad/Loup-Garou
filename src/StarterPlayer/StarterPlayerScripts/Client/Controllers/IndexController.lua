--!strict
-- Thin client glue: wires the Index nav button + remotes to IndexUI. All UI
-- construction lives in IndexUI.lua; all discovery bookkeeping and milestone
-- validation lives server-side in IndexService.lua. This controller never
-- decides what's discovered or what's claimable itself - it only relays
-- server state in and click intents out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local IndexUI = require(Client.UI.IndexUI)

local IndexController = {}

local function onClaimMilestone(milestoneId: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Index.ClaimMilestone):FireServer(milestoneId)
end

function IndexController.Init()
	local root = IndexUI.Init({
		OnClaimMilestone = onClaimMilestone,
	})
	root.Parent = Shell.GetScreenGui()

	Shell.RegisterNavButton({
		Id = "NavIndex",
		Label = "Index",
		IconText = "📖",
		Order = 20,
		Panel = root,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Index.StateUpdated).OnClientEvent:Connect(function(state)
		IndexUI.SetState(state)
	end)
end

return IndexController
