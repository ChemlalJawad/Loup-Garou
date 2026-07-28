--!strict
-- Thin client glue: wires the Quests nav button + remotes to QuestUI. All
-- instance construction lives in QuestUI.lua; all progress tracking and
-- claim validation lives server-side in QuestService.lua.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local QuestUI = require(Client.UI.QuestUI)

local QuestController = {}

local function onClaim(questId: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Quests.ClaimReward):FireServer(questId)
end

function QuestController.Init()
	QuestUI.Init({ OnClaim = onClaim })

	Shell.RegisterNavButton({
		Id = "NavQuests",
		Label = "Quests",
		IconText = "📋",
		Order = 50,
		Panel = QuestUI.GetRoot(),
		OnClick = function() end,
	})

	Net.GetEvent(Constants.REMOTE_NAMES.Quests.StateUpdated).OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			QuestUI.SetState(payload)
		end
	end)

	-- The server already fires a Shared.Notify toast on quest completion; this
	-- only needs to surface the (rare, race-condition-only) claim failures -
	-- a successful claim is reflected by the next StateUpdated push instead.
	Net.GetEvent(Constants.REMOTE_NAMES.Quests.ClaimResult).OnClientEvent:Connect(function(result)
		if type(result) ~= "table" or result.Success then
			return
		end
		Shell.Notify(`Couldn't claim that quest yet ({tostring(result.Reason)}).`, "Warning")
	end)
end

return QuestController
