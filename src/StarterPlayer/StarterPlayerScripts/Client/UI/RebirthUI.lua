--!strict
-- The Rebirth screen: explains the prestige trade-off, shows progress toward
-- eligibility, and requires an explicit confirmation step before firing
-- `Economy.RequestRebirth` - this action wipes Level and Coins, so a
-- mis-click must not be able to trigger it.
--
-- `EconomyService` (server) already implements and validates rebirth
-- entirely; this module is purely the surface for it. Every number shown
-- here (`REBIRTH_MIN_LEVEL`, `REBIRTH_COIN_MULTIPLIER_PER`, `REBIRTH_MAX`) is
-- read from `Constants` rather than duplicated, so tuning changes there never
-- require touching this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local ProgressBarModule = require(ReplicatedStorage.Shared.UIKit.ProgressBar)
local Util = UIKit.Util

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local RebirthUI = {}

export type EconomyState = {
	Level: number,
	Rebirths: number,
	CoinMultiplier: number,
	[string]: any,
}

export type RebirthResult = {
	Success: boolean,
	Reason: string?,
	Rebirths: number?,
	CoinMultiplier: number?,
}

local INELIGIBLE_REASON_TEXT: { [string]: string } = {
	LevelTooLow = `Reach level {Constants.REBIRTH_MIN_LEVEL} to rebirth.`,
	MaxRebirths = `You've reached the maximum of {Constants.REBIRTH_MAX} rebirths.`,
	ProfileNotLoaded = "Your data is still loading - try again in a moment.",
}

local modalRoot: Frame? = nil
local rebirthsLabel: TextLabel? = nil
local bonusLabel: TextLabel? = nil
local afterLabel: TextLabel? = nil
local reasonLabel: TextLabel? = nil
local progressBar: ProgressBarModule.ProgressBarHandle? = nil
local rebirthButton: TextButton? = nil
local confirmOverlay: Frame? = nil

local lastLevel = 1
local lastRebirths = 0
local eligible = false
local ineligibleReason: string? = nil

local function rebirthMultiplierFor(rebirths: number): number
	return 1 + rebirths * Constants.REBIRTH_COIN_MULTIPLIER_PER
end

local function formatMultiplier(multiplier: number): string
	return string.format("x%.2f", multiplier)
end

local function refreshEligibility()
	if lastRebirths >= Constants.REBIRTH_MAX then
		eligible = false
		ineligibleReason = "MaxRebirths"
	elseif lastLevel < Constants.REBIRTH_MIN_LEVEL then
		eligible = false
		ineligibleReason = "LevelTooLow"
	else
		eligible = true
		ineligibleReason = nil
	end
end

local function refreshDisplay()
	refreshEligibility()

	if rebirthsLabel then
		rebirthsLabel.Text = `Rebirths: {lastRebirths} / {Constants.REBIRTH_MAX}`
	end
	if bonusLabel then
		local current = rebirthMultiplierFor(lastRebirths)
		bonusLabel.Text = `Current rebirth bonus: {formatMultiplier(current)} coins`
	end
	if afterLabel then
		local after = rebirthMultiplierFor(lastRebirths + 1)
		afterLabel.Text = `After rebirthing: {formatMultiplier(after)} coins`
	end
	if progressBar then
		progressBar:SetProgress(math.min(lastLevel, Constants.REBIRTH_MIN_LEVEL), Constants.REBIRTH_MIN_LEVEL)
	end
	if reasonLabel then
		if eligible then
			reasonLabel.Text = "You're eligible to rebirth!"
			reasonLabel.TextColor3 = Theme.Color.AccentPrimary
		else
			reasonLabel.Text = INELIGIBLE_REASON_TEXT[ineligibleReason or ""] or "Not eligible yet."
			reasonLabel.TextColor3 = Theme.Color.TextSecondary
		end
	end
	if rebirthButton then
		local color = if eligible then Theme.Color.AccentDanger else Theme.Color.Background
		Util.Tween(rebirthButton, { BackgroundColor3 = color }, Theme.Motion.Fast)
		rebirthButton.TextColor3 = if eligible then Color3.fromRGB(255, 255, 255) else Theme.Color.TextDisabled
	end
end

local function setConfirmVisible(visible: boolean)
	if confirmOverlay then
		confirmOverlay.Visible = visible
	end
end

local function requestRebirth()
	Net.GetEvent(Constants.REMOTE_NAMES.Economy.RequestRebirth):FireServer()
	setConfirmVisible(false)
end

local function buildStatsRow(parent: Instance, layoutOrder: number): TextLabel
	return Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 16,
		LayoutOrder = layoutOrder,
		Parent = parent,
	}) :: TextLabel
end

local function buildConfirmOverlay(parent: Frame)
	local overlay = Util.Create("Frame", {
		Name = "ConfirmOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	}) :: Frame

	local card = UIKit.Panel.new({
		Parent = overlay,
		Name = "ConfirmCard",
		Size = UDim2.fromOffset(420, 220),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Raised = true,
		Padding = Theme.Spacing.L,
	})
	card.ZIndex = 41

	Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Text = "Confirm Rebirth",
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Heading,
		TextSize = 20,
		ZIndex = 41,
		Parent = card,
	})

	Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 90),
		Text = "This resets your Level and Coins back to the start. Your Brainrot collection and index are kept. This cannot be undone.",
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Theme.Font.Body,
		TextSize = 14,
		ZIndex = 41,
		Parent = card,
	})

	local buttonRow = Util.Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -44),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 41,
		Parent = card,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = buttonRow,
	})

	local cancelButton = UIKit.Button.new({
		Text = "Cancel",
		Variant = "Ghost",
		Size = UDim2.fromOffset(120, 40),
		LayoutOrder = 1,
		Parent = buttonRow,
		OnClick = function()
			setConfirmVisible(false)
		end,
	})
	cancelButton.ZIndex = 41

	local confirmButton = UIKit.Button.new({
		Text = "Rebirth Now",
		Variant = "Danger",
		Size = UDim2.fromOffset(150, 40),
		LayoutOrder = 2,
		Parent = buttonRow,
		OnClick = requestRebirth,
	})
	confirmButton.ZIndex = 41

	confirmOverlay = overlay
end

local function build(): Frame
	local modal = UIKit.Modal.new({
		Title = "REBIRTH",
		Subtitle = "Reset your progress for a permanent coin boost",
		Size = UDim2.fromOffset(480, 460),
		AccentColor = Theme.Color.AccentWarning,
		Parent = Shell.GetScreenGui(),
	})

	local explanation = Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 74),
		Text = `Rebirthing resets your Level and Coins back to the start. Your entire Brainrot collection and collection index are kept - nothing you've hatched is lost. In exchange, you gain a permanent +{math.floor(Constants.REBIRTH_COIN_MULTIPLIER_PER * 100)}% Coin multiplier that stacks with every rebirth, forever.`,
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Theme.Font.Body,
		TextSize = 14,
		LayoutOrder = 1,
		Parent = modal.Content,
	}) :: TextLabel

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Theme.Spacing.M),
		Parent = modal.Content,
	})
	explanation.LayoutOrder = 1

	UIKit.Divider.new({ Parent = modal.Content, LayoutOrder = 2 })

	local statsPanel = Util.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 80),
		LayoutOrder = 3,
		Parent = modal.Content,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 2),
		Parent = statsPanel,
	})

	rebirthsLabel = buildStatsRow(statsPanel, 1)
	bonusLabel = buildStatsRow(statsPanel, 2)
	afterLabel = buildStatsRow(statsPanel, 3)
	if afterLabel then
		afterLabel.TextColor3 = Theme.Color.AccentPrimary
	end

	local progressLabel = Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = `Level progress toward rebirth (level {Constants.REBIRTH_MIN_LEVEL} required)`,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 12,
		LayoutOrder = 4,
		Parent = modal.Content,
	}) :: TextLabel

	progressBar = UIKit.ProgressBar.new({
		Parent = modal.Content,
		Size = UDim2.new(1, 0, 0, 22),
		AccentColor = Theme.Color.AccentWarning,
		ShowLabel = true,
		LayoutOrder = 5,
	})

	reasonLabel = Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 13,
		LayoutOrder = 6,
		Parent = modal.Content,
	}) :: TextLabel

	local button = UIKit.Button.new({
		Text = "REBIRTH",
		Variant = "Danger",
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = 7,
		Parent = modal.Content,
		OnClick = function()
			if eligible then
				setConfirmVisible(true)
			else
				Shell.Notify(INELIGIBLE_REASON_TEXT[ineligibleReason or ""] or "Not eligible yet.", "Warning")
			end
		end,
	})
	rebirthButton = button

	buildConfirmOverlay(modal.Root)

	modalRoot = modal.Root
	return modal.Root
end

function RebirthUI.Init()
	if modalRoot then
		return
	end

	local root = build()
	refreshDisplay()

	Shell.RegisterNavButton({
		Id = "NavRebirth",
		Label = "Rebirth",
		IconText = "♻️",
		Order = 90,
		Panel = root,
		OnClick = function()
			refreshDisplay()
		end,
	})
end

-- Fed live level/rebirth state by EconomyController on every
-- `Economy.StateUpdated` push, so the panel is always accurate even if it's
-- opened well after the last rebirth.
function RebirthUI.SetState(state: EconomyState)
	if type(state) ~= "table" then
		return
	end
	lastLevel = state.Level or lastLevel
	lastRebirths = state.Rebirths or lastRebirths
	refreshDisplay()
end

function RebirthUI.HandleRebirthResult(result: RebirthResult)
	if type(result) ~= "table" then
		return
	end
	setConfirmVisible(false)
	if result.Success then
		if result.Rebirths then
			lastRebirths = result.Rebirths
		end
		lastLevel = 1
		refreshDisplay()
	else
		Shell.Notify(INELIGIBLE_REASON_TEXT[result.Reason or ""] or "Rebirth failed.", "Warning")
	end
end

return RebirthUI
