--!strict
-- Builds the Daily Rewards panel: 7 day-cards (current day highlighted, past
-- days marked claimed, future days dimmed) plus a claim button that shows a
-- live countdown when the reward isn't claimable yet. Pure UI construction -
-- never decides eligibility itself, only renders whatever DailyController
-- forwards from the server's StateUpdated/ClaimResult payloads.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local DailyConfig = require(ReplicatedStorage.Shared.Daily.DailyConfig)
local Util = UIKit.Util

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local DailyUI = {}

export type DailyUICallbacks = {
	OnClaim: () -> (),
}

export type DailyStatePayload = {
	Streak: number,
	Claimable: boolean,
	SecondsUntilNext: number,
	NextRewardDay: number,
	MaxDay: number,
}

local PANEL_SIZE = UDim2.new(0, 720, 0, 380)
local PANEL_ID = "NavDaily"

local initialized = false
local callbacks: DailyUICallbacks? = nil

local dayCards: { [number]: { Root: Frame, StatusLabel: TextLabel, Stroke: UIStroke, Wash: Frame } } = {}
local claimButton: TextButton? = nil
local streakLabel: TextLabel? = nil
local countdownLabel: TextLabel? = nil

local lastState: DailyStatePayload? = nil
local secondsRemaining = 0
local heartbeatConnection: RBXScriptConnection? = nil
local accumulator = 0

DailyUI.Root = nil :: Frame?

local function formatReward(reward: DailyConfig.DailyReward): string
	local parts: { string } = {}
	if reward.Coins > 0 then
		table.insert(parts, `{reward.Coins} Coins`)
	end
	if reward.Gems > 0 then
		table.insert(parts, `{reward.Gems} Gems`)
	end
	if reward.BoostName and reward.BoostSeconds then
		local minutes = math.floor(reward.BoostSeconds / 60)
		table.insert(parts, `{reward.BoostName} ({minutes}m)`)
	end
	if #parts == 0 then
		return "-"
	end
	return table.concat(parts, "\n")
end

local function formatCountdown(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	local hours = math.floor(clamped / 3600)
	local minutes = math.floor((clamped % 3600) / 60)
	local secs = clamped % 60
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function createDayCard(parent: Instance, reward: DailyConfig.DailyReward)
	local card = Util.Create("Frame", {
		Name = `Day{reward.Day}`,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 88, 1, 0),
		LayoutOrder = reward.Day,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })

	local stroke = Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Parent = card,
	}) :: UIStroke

	local wash = Util.Create("Frame", {
		Name = "Wash",
		BackgroundColor3 = Theme.Color.AccentPrimary,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = card,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = wash })

	Util.Create("TextLabel", {
		Name = "DayLabel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0, 8),
		Size = UDim2.new(1, -12, 0, 18),
		Text = `DAY {reward.Day}`,
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.SubHeading,
		TextSize = 12,
		ZIndex = 2,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "RewardLabel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0, 30),
		Size = UDim2.new(1, -12, 1, -66),
		Text = formatReward(reward),
		TextColor3 = Theme.Color.TextPrimary,
		TextWrapped = true,
		Font = Theme.Font.Body,
		TextSize = 12,
		ZIndex = 2,
		Parent = card,
	})

	local statusLabel = Util.Create("TextLabel", {
		Name = "StatusLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -12, 0, 18),
		Text = "",
		TextColor3 = Theme.Color.AccentPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 11,
		ZIndex = 2,
		Parent = card,
	}) :: TextLabel

	dayCards[reward.Day] = { Root = card, StatusLabel = statusLabel, Stroke = stroke, Wash = wash }
end

local function refreshCards(state: DailyStatePayload)
	for day, entry in dayCards do
		-- NextRewardDay is "the day tier a claim right now would pay", computed
		-- purely from elapsed time (see DailyRewardService.evaluate) - it's
		-- always Streak+1 within the forgiveness window and 1 after a reset, so
		-- "day < NextRewardDay" is exactly the set of days already claimed in
		-- the current streak.
		local past = day < state.NextRewardDay
		local isCurrent = day == state.NextRewardDay

		if isCurrent then
			entry.Stroke.Color = Theme.Color.AccentPrimary
			entry.Stroke.Thickness = Theme.Stroke.Thick
			entry.Wash.BackgroundTransparency = 0.75
			entry.StatusLabel.Text = if state.Claimable then "CLAIM NOW" else "UP NEXT"
			entry.StatusLabel.TextColor3 = Theme.Color.AccentPrimary
			entry.Root.BackgroundTransparency = 0
		elseif past then
			entry.Stroke.Color = Theme.Color.Stroke
			entry.Stroke.Thickness = Theme.Stroke.Thin
			entry.Wash.BackgroundTransparency = 1
			entry.StatusLabel.Text = "CLAIMED"
			entry.StatusLabel.TextColor3 = Theme.Color.TextSecondary
			entry.Root.BackgroundTransparency = 0.35
		else
			entry.Stroke.Color = Theme.Color.Stroke
			entry.Stroke.Thickness = Theme.Stroke.Thin
			entry.Wash.BackgroundTransparency = 1
			entry.StatusLabel.Text = ""
			entry.Root.BackgroundTransparency = 0.55
		end
	end
end

local function refreshClaimButton(state: DailyStatePayload)
	local button = claimButton
	if not button then
		return
	end
	if state.Claimable then
		button.Text = "CLAIM REWARD"
		button.Active = true
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.Color.AccentPrimary
	else
		button.Text = `NEXT IN {formatCountdown(secondsRemaining)}`
		button.Active = false
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.Color.Background
	end
end

local function tick(dt: number)
	if not lastState or lastState.Claimable then
		return
	end
	accumulator += dt
	if accumulator < 1 then
		return
	end
	accumulator = 0
	secondsRemaining = math.max(0, secondsRemaining - 1)
	refreshClaimButton(lastState)
	if secondsRemaining <= 0 and countdownLabel then
		countdownLabel.Text = "Refresh to claim!"
	end
end

function DailyUI.Init(props: DailyUICallbacks)
	if initialized then
		return
	end
	initialized = true
	callbacks = props

	local modal = UIKit.Modal.new({
		Title = "DAILY REWARDS",
		Subtitle = "Come back every day - miss a day and it's forgiven, miss two and your streak resets.",
		Size = PANEL_SIZE,
		Parent = Shell.GetScreenGui(),
		OnClose = function()
			Shell.ClosePanel(PANEL_ID)
		end,
	})
	DailyUI.Root = modal.Root

	local cardRow = Util.Create("Frame", {
		Name = "CardRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 200),
		Parent = modal.Content,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = cardRow,
	})

	for _, reward in DailyConfig.Rewards do
		createDayCard(cardRow, reward)
	end

	streakLabel = Util.Create("TextLabel", {
		Name = "StreakLabel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 214),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "Streak: 0 days",
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.Body,
		TextSize = 14,
		Parent = modal.Content,
	}) :: TextLabel

	local button = UIKit.Button.new({
		Text = "CLAIM REWARD",
		Variant = "Primary",
		Size = UDim2.new(0, 280, 0, 52),
		Position = UDim2.new(0.5, 0, 0, 256),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = modal.Content,
		OnClick = function()
			if lastState and lastState.Claimable and callbacks then
				callbacks.OnClaim()
			end
		end,
	})
	claimButton = button

	countdownLabel = Util.Create("TextLabel", {
		Name = "CountdownHint",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 318),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextColor3 = Theme.Color.TextDisabled,
		Font = Theme.Font.Body,
		TextSize = 12,
		Parent = modal.Content,
	}) :: TextLabel

	heartbeatConnection = RunService.Heartbeat:Connect(tick)
end

function DailyUI.SetState(state: DailyStatePayload)
	lastState = state
	secondsRemaining = state.SecondsUntilNext
	accumulator = 0

	if streakLabel then
		streakLabel.Text = `Streak: {state.Streak} day{if state.Streak == 1 then "" else "s"}`
	end
	if countdownLabel then
		countdownLabel.Text = if state.Claimable then "" else "Come back after the countdown to keep your streak."
	end

	refreshCards(state)
	refreshClaimButton(state)
end

function DailyUI.Toggle()
	Shell.TogglePanel(PANEL_ID)
end

return DailyUI
