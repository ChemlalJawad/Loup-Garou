--!strict
-- Thin client glue: registers the Leaderboards nav button/panel and forwards
-- Leaderboard_Updated pushes into LeaderboardUI. All instance construction
-- lives in LeaderboardUI.lua; all ranking/publishing logic lives server-side
-- in LeaderboardService.lua. This controller never computes ranks itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local LeaderboardUI = require(Client.UI.LeaderboardUI)

local LeaderboardController = {}

function LeaderboardController.Init()
	local root = LeaderboardUI.Init()
	root.Parent = Shell.GetScreenGui()

	Shell.RegisterNavButton({
		Id = "NavLeaderboard",
		Label = "Leaderboards",
		IconText = "🏆",
		Order = 80,
		Panel = root,
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Leaderboard.Updated).OnClientEvent:Connect(function(state: any)
		if type(state) ~= "table" then
			return
		end
		LeaderboardUI.SetState(state)
	end)
end

return LeaderboardController
