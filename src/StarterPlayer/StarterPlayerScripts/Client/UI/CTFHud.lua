--!strict
-- Builds the persistent Brain-Rot CTF HUD overlay: round timer, score, a
-- compact flag-status readout, and an ability button with a cooldown fill.
-- Owns no remote/network code - CTFController pushes data in (SetTeam,
-- SetScore, SetRoundState, SetFlagState, SetAbilityCooldown) and receives the
-- ability button click out via the OnUseAbility handler passed to Init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Shell = require(StarterPlayer.StarterPlayerScripts.Client.UI.Shell)

local Util = UIKit.Util

local CTFHud = {}

export type Handlers = {
	OnUseAbility: () -> (),
}

export type FlagStatusInfo = {
	State: string,
	CarrierName: string?,
}

export type FlagStatusPayload = { [string]: FlagStatusInfo }

-- Module state (built once in Init).
local handlers: Handlers? = nil

local root: Frame? = nil
local timerLabel: TextLabel? = nil
local redScoreLabel: TextLabel? = nil
local blueScoreLabel: TextLabel? = nil
local yourFlagLabel: TextLabel? = nil
local enemyFlagLabel: TextLabel? = nil

local abilityButtonFrame: Frame? = nil
local abilityButton: TextButton? = nil
local abilityCooldownOverlay: Frame? = nil

local currentTeamId: string? = nil

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function otherTeamId(teamId: string): string
	return if teamId == "Red" then "Blue" else "Red"
end

local function formatClock(seconds: number): string
	local totalSeconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(totalSeconds / 60)
	local secs = totalSeconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local function describeFlag(info: FlagStatusInfo?): string
	if not info then
		return "Unknown"
	end
	if info.State == "AtBase" then
		return "Home"
	elseif info.State == "Carried" then
		return if info.CarrierName then `Carried by {info.CarrierName}` else "Carried"
	elseif info.State == "Dropped" then
		return "Dropped"
	end
	return info.State
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function buildScoreRow(parent: Instance): Frame
	local row = Util.Create("Frame", {
		Name = "ScoreRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = parent,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "RedCaption",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 42, 1, 0),
		Text = "RED",
		Font = Theme.Font.SubHeading,
		TextSize = 14,
		TextColor3 = Theme.Team.Red,
		LayoutOrder = 1,
		Parent = row,
	})

	redScoreLabel = Util.Create("TextLabel", {
		Name = "RedScore",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 40, 1, 0),
		Text = "0",
		Font = Theme.Font.Heading,
		TextSize = 26,
		TextColor3 = Theme.Team.Red,
		LayoutOrder = 2,
		Parent = row,
	}) :: TextLabel

	Util.Create("TextLabel", {
		Name = "Separator",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 18, 1, 0),
		Text = "-",
		Font = Theme.Font.Heading,
		TextSize = 22,
		TextColor3 = Theme.Color.TextSecondary,
		LayoutOrder = 3,
		Parent = row,
	})

	blueScoreLabel = Util.Create("TextLabel", {
		Name = "BlueScore",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 40, 1, 0),
		Text = "0",
		Font = Theme.Font.Heading,
		TextSize = 26,
		TextColor3 = Theme.Team.Blue,
		LayoutOrder = 4,
		Parent = row,
	}) :: TextLabel

	Util.Create("TextLabel", {
		Name = "BlueCaption",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 42, 1, 0),
		Text = "BLUE",
		Font = Theme.Font.SubHeading,
		TextSize = 14,
		TextColor3 = Theme.Team.Blue,
		LayoutOrder = 5,
		Parent = row,
	})

	return row
end

local function buildRoot(parent: Instance)
	local panel = UIKit.Panel.new({
		Name = "CTFHud",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.new(0, 380, 0, 132),
		Padding = 14,
	})
	panel.Visible = false
	root = panel

	timerLabel = Util.Create("TextLabel", {
		Name = "Timer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Waiting for players...",
		Font = Theme.Font.SubHeading,
		TextSize = 15,
		TextColor3 = Theme.Color.TextSecondary,
		Parent = panel,
	}) :: TextLabel

	local scoreRow = buildScoreRow(panel)
	scoreRow.Position = UDim2.new(0, 0, 0, 24)

	yourFlagLabel = Util.Create("TextLabel", {
		Name = "YourFlag",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 68),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "Your Flag: -",
		Font = Theme.Font.Body,
		TextSize = 14,
		TextColor3 = Theme.Color.TextPrimary,
		Parent = panel,
	}) :: TextLabel

	enemyFlagLabel = Util.Create("TextLabel", {
		Name = "EnemyFlag",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 90),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "Enemy Flag: -",
		Font = Theme.Font.Body,
		TextSize = 14,
		TextColor3 = Theme.Color.TextPrimary,
		Parent = panel,
	}) :: TextLabel
end

local function buildAbilityButton(parent: Instance)
	local frame = Util.Create("Frame", {
		Name = "AbilityButtonFrame",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -90),
		Size = UDim2.new(0, 84, 0, 84),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	frame.Visible = false
	abilityButtonFrame = frame

	local button = Util.Create("TextButton", {
		Name = "AbilityButton",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Text = "Q",
		Font = Theme.Font.Heading,
		TextSize = 30,
		TextColor3 = Theme.Color.TextPrimary,
		ClipsDescendants = true,
		Parent = frame,
	}) :: TextButton
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Large, Parent = button })
	Util.Create("UIStroke", {
		Color = Theme.Color.AccentInfo,
		Thickness = Theme.Stroke.Regular,
		Parent = button,
	})
	abilityButton = button

	local overlay = Util.Create("Frame", {
		Name = "CooldownOverlay",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Theme.Color.Background,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex + 1,
		Parent = button,
	}) :: Frame
	abilityCooldownOverlay = overlay

	button.MouseButton1Click:Connect(function()
		if handlers and handlers.OnUseAbility then
			handlers.OnUseAbility()
		end
	end)
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function CTFHud.Init(hdlrs: Handlers)
	if root then
		return
	end
	handlers = hdlrs

	local screenGui = Shell.GetScreenGui()
	buildRoot(screenGui)
	buildAbilityButton(screenGui)
end

function CTFHud.SetTeam(teamId: string?)
	currentTeamId = teamId
	local visible = teamId ~= nil
	if root then
		root.Visible = visible
	end
	if abilityButtonFrame then
		abilityButtonFrame.Visible = visible
	end
end

function CTFHud.SetScore(red: number, blue: number)
	if redScoreLabel then
		redScoreLabel.Text = tostring(red)
	end
	if blueScoreLabel then
		blueScoreLabel.Text = tostring(blue)
	end
end

function CTFHud.SetRoundState(state: string, timeRemaining: number)
	if not timerLabel then
		return
	end
	if state == "Waiting" then
		timerLabel.Text = "Waiting for players..."
	elseif state == "InProgress" then
		timerLabel.Text = `Round ends in {formatClock(timeRemaining)}`
	elseif state == "RoundOver" then
		timerLabel.Text = "Round Over"
	else
		timerLabel.Text = state
	end
end

function CTFHud.SetFlagState(payload: FlagStatusPayload)
	if not currentTeamId then
		return
	end
	local mine = payload[currentTeamId]
	local enemy = payload[otherTeamId(currentTeamId)]

	if yourFlagLabel then
		yourFlagLabel.Text = `Your Flag: {describeFlag(mine)}`
	end
	if enemyFlagLabel then
		enemyFlagLabel.Text = `Enemy Flag: {describeFlag(enemy)}`
	end
end

-- `remainingSeconds` of `totalSeconds` left on cooldown. Pass 0 to clear.
function CTFHud.SetAbilityCooldown(remainingSeconds: number, totalSeconds: number)
	if not abilityCooldownOverlay then
		return
	end
	if remainingSeconds <= 0 then
		Util.Tween(abilityCooldownOverlay, { Size = UDim2.new(1, 0, 0, 0) }, Theme.Motion.Fast)
		return
	end
	abilityCooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	Util.Tween(abilityCooldownOverlay, { Size = UDim2.new(1, 0, 0, 0) }, remainingSeconds, Enum.EasingStyle.Linear)
end

return CTFHud
