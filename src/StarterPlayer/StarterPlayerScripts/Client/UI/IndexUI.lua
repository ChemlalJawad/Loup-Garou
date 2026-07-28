--!strict
-- Builds the Collection Index screen entirely from UIKit components: a
-- completion meter, a rarity tab bar over a grid of all 16 Brainrots
-- (discovered entries show name/rarity/hatch count, undiscovered show the
-- ItemCard `Locked` silhouette state), and a milestones list with CLAIM
-- buttons that light up once satisfied.
--
-- Owns no remote/network code - IndexController pushes server state in via
-- SetState() and receives click intents out via the handlers passed to
-- Init(). This module never decides whether a milestone is actually
-- claimable on its own authority; it only reflects IndexConfig.EvaluateMilestone
-- (the same pure check the server re-validates) so the CLAIM button state
-- always matches what the server would say.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local IndexConfig = require(ReplicatedStorage.Shared.Index.IndexConfig)

local Util = UIKit.Util

local IndexUI = {}

export type IndexHandlers = {
	OnClaimMilestone: (milestoneId: string) -> (),
}

export type IndexState = {
	Index: { [string]: number },
	Claimed: { [string]: boolean },
}

-- Module state (built once in Init).
local handlers: IndexHandlers? = nil
local modalRoot: Frame? = nil
local subtitleLabel: TextLabel? = nil
local meter: any = nil -- UIKit.ProgressBar.ProgressBarHandle
local grid: any = nil -- UIKit.ScrollGrid.ScrollGridHandle
local milestonesGrid: any = nil -- UIKit.ScrollGrid.ScrollGridHandle
local tabBar: any = nil -- UIKit.TabBar.TabBarHandle

local currentIndex: { [string]: number } = {}
local currentClaimed: { [string]: boolean } = {}
local currentRarityFilter: string = "All"

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function formatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	local withSeparators = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return withSeparators
end

local function formatReward(reward: IndexConfig.RewardBundle): string
	local parts: { string } = {}
	if reward.Coins and reward.Coins > 0 then
		table.insert(parts, `{formatNumber(reward.Coins)} Coins`)
	end
	if reward.Gems and reward.Gems > 0 then
		table.insert(parts, `{formatNumber(reward.Gems)} Gems`)
	end
	if reward.XP and reward.XP > 0 then
		table.insert(parts, `{formatNumber(reward.XP)} XP`)
	end
	return table.concat(parts, "  •  ")
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

local function renderMeter()
	if not meter then
		return
	end
	local discovered = IndexConfig.DiscoveredCount(currentIndex)
	local total = IndexConfig.TotalCount()
	meter:SetProgress(discovered, total)
	if subtitleLabel then
		subtitleLabel.Text = `{discovered}/{total} discovered`
	end
end

local function renderGrid()
	if not grid then
		return
	end
	grid:Clear()

	local entries = if currentRarityFilter == "All"
		then IndexConfig.AllEntries()
		else IndexConfig.EntriesByRarity(currentRarityFilter)

	for order, entry in entries do
		local count = currentIndex[entry.Id] or 0
		local discovered = count > 0

		UIKit.ItemCard.new({
			Parent = grid.Root,
			LayoutOrder = order,
			Title = entry.Name,
			Rarity = entry.Rarity,
			Subtitle = if discovered then `Hatched x{count}` else nil,
			Locked = not discovered,
		})
	end
end

local function renderMilestoneRow(milestone: IndexConfig.Milestone, order: number)
	if not milestonesGrid then
		return
	end

	local claimed = currentClaimed[milestone.Id] == true
	local satisfied = IndexConfig.EvaluateMilestone(milestone.Id, currentIndex)
	local progressCurrent, progressTotal = IndexConfig.MilestoneProgress(milestone.Id, currentIndex)
	local claimable = satisfied and not claimed

	local row = Util.Create("Frame", {
		Name = `Milestone_{milestone.Id}`,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 84),
		LayoutOrder = order,
		Parent = milestonesGrid.Root,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = row })
	Util.Create("UIStroke", {
		Color = if claimable then Theme.Color.AccentPrimary else Theme.Color.Stroke,
		Thickness = if claimable then Theme.Stroke.Regular else Theme.Stroke.Thin,
		Transparency = if claimed then 0.6 else 0,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -140, 0, 20),
		Text = milestone.Label,
		TextColor3 = if claimed then Theme.Color.TextSecondary else Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 15,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 30),
		Size = UDim2.new(1, -140, 0, 16),
		Text = milestone.Description,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 12,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Reward",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 48),
		Size = UDim2.new(1, -140, 0, 16),
		Text = formatReward(milestone.Reward) .. if milestone.PermanentLuckBoost then "  •  Permanent Luck Boost" else "",
		TextColor3 = Theme.Color.AccentWarning,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 12,
		Parent = row,
	})

	local rowProgress = UIKit.ProgressBar.new({
		Parent = row,
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.new(1, -140, 0, 8),
		AccentColor = if claimed then Theme.Color.Stroke else Theme.RarityColor(milestone.Rarity or "Common"),
	})
	rowProgress:SetProgress(progressCurrent, progressTotal, false)

	local buttonText = if claimed then "CLAIMED" elseif claimable then "CLAIM" else `{progressCurrent}/{progressTotal}`
	local button = UIKit.Button.new({
		Text = buttonText,
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		Variant = if claimable then "Primary" else "Ghost",
		OnClick = if claimable
			then function()
				if handlers then
					handlers.OnClaimMilestone(milestone.Id)
				end
			end
			else nil,
	})
	button.Active = claimable
	button.AutoButtonColor = false
end

local function renderMilestones()
	if not milestonesGrid then
		return
	end
	milestonesGrid:Clear()
	for order, milestone in IndexConfig.AllMilestones() do
		renderMilestoneRow(milestone, order)
	end
end

local function renderAll()
	renderMeter()
	renderGrid()
	renderMilestones()
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function IndexUI.Init(props: IndexHandlers): Frame
	handlers = props

	local modal = UIKit.Modal.new({
		Title = "INDEX",
		Subtitle = "0/16 discovered",
		Size = UDim2.fromOffset(860, 640),
		AccentColor = Theme.Color.AccentSecondary,
	})
	modalRoot = modal.Root
	subtitleLabel = modal.SubtitleLabel

	local content = modal.Content
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, Theme.Spacing.S),
		Parent = content,
	})

	local meterHandle = UIKit.ProgressBar.new({
		Parent = content,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 22),
		AccentColor = Theme.Color.AccentSecondary,
		ShowLabel = true,
	})
	meter = meterHandle

	local tabs = { { Id = "All", Label = "All" } }
	for _, rarity in Constants.RARITY_ORDER do
		table.insert(tabs, { Id = rarity, Label = rarity })
	end

	local tabBarFrame = Util.Create("Frame", {
		Name = "TabBarRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 2,
		Parent = content,
	}) :: Frame

	local tabBarHandle = UIKit.TabBar.new({
		Tabs = tabs,
		Parent = tabBarFrame,
		Size = UDim2.new(1, 0, 1, 0),
		AccentColor = Theme.Color.AccentSecondary,
		OnChange = function(tabId: string)
			currentRarityFilter = tabId
			renderGrid()
		end,
	})
	tabBar = tabBarHandle

	local gridHandle = UIKit.ScrollGrid.new({
		Parent = content,
		Size = UDim2.new(1, 0, 0, 260),
		CellSize = UDim2.fromOffset(150, 170),
	})
	gridHandle.Root.LayoutOrder = 3
	grid = gridHandle

	Util.Create("Frame", {
		Name = "Spacer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 2),
		LayoutOrder = 4,
		Parent = content,
	})
	UIKit.Divider.new({ Parent = content, LayoutOrder = 5 })

	Util.Create("TextLabel", {
		Name = "MilestonesHeader",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 6,
		Text = "MILESTONES",
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 14,
		Parent = content,
	})

	local milestonesHandle = UIKit.ScrollGrid.new({
		Parent = content,
		Size = UDim2.new(1, 0, 0, 190),
		Vertical = true,
	})
	milestonesHandle.Root.LayoutOrder = 7
	milestonesGrid = milestonesHandle

	renderAll()

	return modal.Root
end

-- Called by IndexController whenever Index_StateUpdated fires.
function IndexUI.SetState(state: IndexState)
	currentIndex = state.Index or {}
	currentClaimed = state.Claimed or {}
	renderAll()
end

return IndexUI
