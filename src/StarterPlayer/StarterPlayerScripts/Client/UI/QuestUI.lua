--!strict
-- All Quest screen instance construction lives here. QuestController.lua
-- stays thin: it wires remotes/nav and calls into this module.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local ScrollGrid = require(ReplicatedStorage.Shared.UIKit.ScrollGrid)
local Util = UIKit.Util

local QuestUI = {}

export type QuestEntry = {
	Id: string,
	Name: string,
	Description: string,
	Type: string,
	Target: number,
	Progress: number,
	Claimed: boolean,
	Reward: { Coins: number?, Gems: number?, XP: number? },
	Tier: string,
}

export type QuestStatePayload = {
	Daily: { QuestEntry },
	Weekly: { QuestEntry },
	NextDailyRefreshAt: number,
	NextWeeklyRefreshAt: number,
	ServerTime: number,
}

export type QuestUIProps = {
	OnClaim: (questId: string) -> (),
}

local root: Frame? = nil
local scrollGrid: ScrollGrid.ScrollGridHandle? = nil
local countdownLabel: TextLabel? = nil
local currentTab: string = "Daily"
local latestState: QuestStatePayload? = nil
local onClaimCallback: ((string) -> ())? = nil
-- serverTime (as of the last push) minus the client's os.time() at receipt,
-- so the countdown reads against the server's clock rather than assuming the
-- client's clock is in sync.
local clockOffset: number = 0

local function formatReward(reward: { Coins: number?, Gems: number?, XP: number? }): string
	local parts: { string } = {}
	if reward.Coins and reward.Coins > 0 then
		table.insert(parts, `+{reward.Coins} Coins`)
	end
	if reward.Gems and reward.Gems > 0 then
		table.insert(parts, `+{reward.Gems} Gems`)
	end
	if reward.XP and reward.XP > 0 then
		table.insert(parts, `+{reward.XP} XP`)
	end
	if #parts == 0 then
		return "No reward"
	end
	return table.concat(parts, "  ")
end

local function formatDuration(seconds: number): string
	if seconds <= 0 then
		return "any moment now"
	end
	local days = math.floor(seconds / 86400)
	seconds -= days * 86400
	local hours = math.floor(seconds / 3600)
	seconds -= hours * 3600
	local minutes = math.floor(seconds / 60)
	seconds -= minutes * 60

	if days > 0 then
		return string.format("%dd %02dh %02dm", days, hours, minutes)
	end
	return string.format("%02dh %02dm %02ds", hours, minutes, seconds)
end

local function buildQuestRow(parent: Instance, entry: QuestEntry, order: number)
	local complete = entry.Progress >= entry.Target

	local row = Util.Create("Frame", {
		Name = "Quest_" .. entry.Id,
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = if entry.Claimed then 0.4 else 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -4, 0, 96),
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = row })
	Util.Create("UIStroke", {
		Color = if complete and not entry.Claimed then Theme.Color.AccentPrimary else Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = if complete and not entry.Claimed then 0.2 else 0.5,
		Parent = row,
	})
	Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0.62, 0, 0, 20),
		Text = entry.Name,
		TextColor3 = if entry.Claimed then Theme.Color.TextDisabled else Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(0.62, 0, 0, 18),
		Text = entry.Description,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 13,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Reward",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(0.62, 0, 0, 16),
		Text = formatReward(entry.Reward),
		TextColor3 = Theme.Color.AccentWarning,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Mono,
		TextSize = 13,
		Parent = row,
	})

	local progressBar = UIKit.ProgressBar.new({
		Parent = row,
		Position = UDim2.new(0, 0, 0, 66),
		Size = UDim2.new(0.62, 0, 0, 18),
		ShowLabel = true,
		AccentColor = if entry.Claimed then Theme.Color.TextDisabled else Theme.Color.AccentPrimary,
	})
	progressBar:SetProgress(entry.Progress, entry.Target, false)

	local claimLabel = if entry.Claimed then "CLAIMED" elseif complete then "CLAIM" else "IN PROGRESS"
	local claimVariant = if entry.Claimed then "Ghost" elseif complete then "Primary" else "Secondary"

	local claimButton = UIKit.Button.new({
		Text = claimLabel,
		Variant = claimVariant :: any,
		Size = UDim2.new(0, 128, 0, 42),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Parent = row,
		OnClick = if complete and not entry.Claimed and onClaimCallback
			then function()
				(onClaimCallback :: (string) -> ())(entry.Id)
			end
			else nil,
	})
	claimButton.Active = complete and not entry.Claimed
	if not (complete and not entry.Claimed) then
		claimButton.AutoButtonColor = false
		claimButton.BackgroundTransparency = if entry.Claimed then 0.6 else 0.35
	end
end

local function renderList()
	if not scrollGrid then
		return
	end
	local grid = scrollGrid :: ScrollGrid.ScrollGridHandle
	grid:Clear()
	if not latestState then
		return
	end

	local list = if currentTab == "Daily" then latestState.Daily else latestState.Weekly
	for index, entry in list do
		buildQuestRow(grid.Root, entry, index)
	end
end

local function updateCountdown()
	if not countdownLabel or not latestState then
		return
	end
	local now = os.time() + clockOffset
	local dailyRemaining = latestState.NextDailyRefreshAt - now
	local weeklyRemaining = latestState.NextWeeklyRefreshAt - now
	local label: TextLabel = countdownLabel :: TextLabel
	label.Text = `Daily resets in {formatDuration(dailyRemaining)}   |   Weekly resets in {formatDuration(weeklyRemaining)}`
end

function QuestUI.Init(props: QuestUIProps)
	onClaimCallback = props.OnClaim

	local modal = UIKit.Modal.new({
		Title = "QUESTS",
		Subtitle = "Daily & weekly goals - come back tomorrow for more",
		Size = UDim2.fromOffset(720, 560),
	})
	root = modal.Root

	UIKit.TabBar.new({
		Tabs = {
			{ Id = "Daily", Label = "DAILY" },
			{ Id = "Weekly", Label = "WEEKLY" },
		},
		Parent = modal.Content,
		Size = UDim2.new(1, 0, 0, 40),
		OnChange = function(tabId: string)
			currentTab = tabId
			renderList()
		end,
	})

	countdownLabel = Util.Create("TextLabel", {
		Name = "Countdown",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0, 46),
		Size = UDim2.new(1, -8, 0, 18),
		Text = "",
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 13,
		Parent = modal.Content,
	}) :: TextLabel

	scrollGrid = UIKit.ScrollGrid.new({
		Parent = modal.Content,
		Vertical = true,
		Position = UDim2.new(0, 0, 0, 74),
		Size = UDim2.new(1, 0, 1, -74),
	})

	local lastTick = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastTick < 1 then
			return
		end
		lastTick = now
		updateCountdown()
	end)
end

function QuestUI.GetRoot(): Frame
	assert(root, "QuestUI.Init must be called before QuestUI.GetRoot")
	return root :: Frame
end

function QuestUI.SetState(payload: QuestStatePayload)
	latestState = payload
	clockOffset = payload.ServerTime - os.time()
	renderList()
	updateCountdown()
end

return QuestUI
