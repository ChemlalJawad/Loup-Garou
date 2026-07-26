--!strict
-- Thin client glue: wires the CTF nav button, the ability key/button, and all
-- CTF_* remotes to CTFHud. All UI construction lives in CTFHud.lua; all game
-- logic (team balancing, flag state, tagging, round timing, ability
-- resolution) lives server-side in TeamService.lua / CTFService.lua. This
-- controller never decides outcomes itself, it only requests and displays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)
local CTFHud = require(Client.UI.CTFHud)

local CTFController = {}

local ABILITY_KEY = Enum.KeyCode.Q

local function requestJoinTeam()
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.RequestJoinTeam):FireServer()
end

local function requestUseAbility()
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.UseAbility):FireServer()
end

local function onInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == ABILITY_KEY then
		requestUseAbility()
	end
end

local function onTeamAssigned(teamId: string)
	CTFHud.SetTeam(teamId)
	Shell.Notify(`Joined {teamId == "Red" and "Team Ember" or "Team Frost"}! Capture the enemy flag.`, "Success")
end

local function onFlagStateUpdated(payload: CTFHud.FlagStatusPayload)
	CTFHud.SetFlagState(payload)
end

local function onScoreUpdated(red: number, blue: number)
	CTFHud.SetScore(red, blue)
end

local function onRoundStateUpdated(state: string, timeRemaining: number, red: number, blue: number)
	CTFHud.SetRoundState(state, timeRemaining)
	CTFHud.SetScore(red, blue)
end

local function onAbilityFeedback(payload: { [string]: any })
	if payload.Success then
		CTFHud.SetAbilityCooldown(payload.Cooldown or 0, payload.Cooldown or 0)
		return
	end

	if payload.Reason == "OnCooldown" then
		local remaining = payload.RemainingSeconds or 0
		Shell.Notify(`Ability on cooldown ({math.ceil(remaining)}s)`, "Warning")
	elseif payload.Reason == "NotOnTeam" then
		Shell.Notify("Join Brain-Rot CTF to use your ability!", "Warning")
	elseif payload.Reason == "NoBrainrotEquipped" then
		Shell.Notify("Equip a Brainrot to use its ability!", "Warning")
	end
end

function CTFController.Init()
	CTFHud.Init({ OnUseAbility = requestUseAbility })

	Shell.RegisterNavButton({
		Id = "NavCTF",
		Label = "Play CTF",
		IconText = "⚔️",
		OnClick = requestJoinTeam,
	})

	UserInputService.InputBegan:Connect(onInputBegan)

	Net.GetEvent(Constants.REMOTE_NAMES.CTF.TeamAssigned).OnClientEvent:Connect(onTeamAssigned)
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.FlagStateUpdated).OnClientEvent:Connect(onFlagStateUpdated)
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.ScoreUpdated).OnClientEvent:Connect(onScoreUpdated)
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.RoundStateUpdated).OnClientEvent:Connect(onRoundStateUpdated)
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.AbilityFeedback).OnClientEvent:Connect(onAbilityFeedback)
end

return CTFController
