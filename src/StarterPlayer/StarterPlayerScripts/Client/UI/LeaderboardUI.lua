--!strict
-- Builds the Leaderboards screen: one tab per Constants.LEADERBOARD_KEYS,
-- ranked rows in a scrolling list, top-3 gold/silver/bronze treatment, a
-- pinned footer showing the local player's own standing, and a
-- "last updated Ns ago" line so an empty board reads as "not loaded yet"
-- rather than "broken". Pure presentation - LeaderboardController owns the
-- remote wiring and just calls LeaderboardUI.SetState with whatever the
-- server last pushed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local LeaderboardUI = {}

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	Value: number,
}

export type BoardCache = {
	Entries: { LeaderboardEntry },
	UpdatedAt: number,
}

export type OwnEntry = {
	Value: number,
	Rank: number?,
}

export type LeaderboardState = {
	Boards: { [string]: BoardCache },
	Own: { [string]: OwnEntry },
}

local TAB_ORDER = { "Coins", "FlagCaptures", "EggsHatched", "Level" }
local TAB_LABELS: { [string]: string } = {
	Coins = "COINS",
	FlagCaptures = "CAPTURES",
	EggsHatched = "EGGS HATCHED",
	Level = "LEVEL",
}

local RANK_ACCENT: { [number]: Color3 } = {
	[1] = Theme.Color.AccentWarning, -- gold
	[2] = Color3.fromRGB(200, 206, 214), -- silver
	[3] = Color3.fromRGB(205, 138, 84), -- bronze
}

local localPlayer = Players.LocalPlayer

local currentState: LeaderboardState = { Boards = {}, Own = {} }
local activeTab = TAB_ORDER[1]

local scrollGrid: any = nil -- UIKit.ScrollGridHandle
local updatedLabel: TextLabel? = nil
local footerRankLabel: TextLabel? = nil
local footerNameLabel: TextLabel? = nil
local footerValueLabel: TextLabel? = nil
local footerFrame: Frame? = nil

local function formatValue(value: number): string
	local formatted = tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return formatted
end

local function formatAgo(updatedAt: number): string
	if updatedAt <= 0 then
		return "not loaded yet"
	end
	local seconds = math.max(0, os.time() - updatedAt)
	if seconds < 60 then
		return `updated {seconds}s ago`
	end
	local minutes = math.floor(seconds / 60)
	return `updated {minutes}m ago`
end

local function buildRow(entry: LeaderboardEntry, layoutOrder: number, isSelf: boolean): Frame
	local accent = RANK_ACCENT[entry.Rank]

	local row = Util.Create("Frame", {
		Name = `Row_{entry.Rank}`,
		BackgroundColor3 = if isSelf then Theme.Color.AccentPrimary elseif accent then accent else Theme.Color.SurfaceRaised,
		BackgroundTransparency = if isSelf then 0.82 elseif accent then 0.85 else 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = layoutOrder,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = row })
	if isSelf then
		Util.Create("UIStroke", {
			Color = Theme.Color.AccentPrimary,
			Thickness = Theme.Stroke.Regular,
			Transparency = 0.2,
			Parent = row,
		})
	elseif accent then
		Util.Create("UIStroke", {
			Color = accent,
			Thickness = Theme.Stroke.Thin,
			Transparency = 0.4,
			Parent = row,
		})
	end

	Util.Create("TextLabel", {
		Name = "Rank",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(0, 56, 1, 0),
		Text = `#{entry.Rank}`,
		TextColor3 = if accent then accent else Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = if accent then 18 else 15,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 74, 0, 0),
		Size = UDim2.new(1, -220, 1, 0),
		Text = if isSelf then `{entry.Name} (you)` else entry.Name,
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = if isSelf then Theme.Font.SubHeading else Theme.Font.Body,
		TextSize = 15,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 140, 1, 0),
		Text = formatValue(entry.Value),
		TextColor3 = Theme.Color.AccentPrimary,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Font.Mono,
		TextSize = 15,
		Parent = row,
	})

	return row
end

local function refreshFooter()
	if not footerFrame or not footerRankLabel or not footerNameLabel or not footerValueLabel then
		return
	end

	local board = currentState.Boards[activeTab]
	local own = currentState.Own[activeTab]

	if not own then
		footerFrame.Visible = false
		return
	end

	-- If the local player is already visible in the top list, the pinned
	-- footer would just duplicate that row - only show it when they're NOT in
	-- the currently rendered top N, so they always see where they stand
	-- without cluttering the common case.
	local inTop = false
	if board then
		for _, entry in board.Entries do
			if entry.UserId == localPlayer.UserId then
				inTop = true
				break
			end
		end
	end

	if inTop then
		footerFrame.Visible = false
		return
	end

	footerFrame.Visible = true
	footerRankLabel.Text = if own.Rank then `#{own.Rank}` else "Unranked"
	footerNameLabel.Text = localPlayer.Name .. " (you)"
	footerValueLabel.Text = formatValue(own.Value)
end

local function renderTab(key: string)
	if not scrollGrid then
		return
	end
	scrollGrid:Clear()

	local board = currentState.Boards[key]
	if updatedLabel then
		updatedLabel.Text = if board then formatAgo(board.UpdatedAt) else "not loaded yet"
	end

	if not board or #board.Entries == 0 then
		Util.Create("TextLabel", {
			Name = "Empty",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 60),
			Text = "No rankings yet - check back soon.",
			TextColor3 = Theme.Color.TextSecondary,
			Font = Theme.Font.Body,
			TextSize = 14,
			Parent = scrollGrid.Root,
		})
	else
		for _, entry in board.Entries do
			local isSelf = entry.UserId == localPlayer.UserId
			local row = buildRow(entry, entry.Rank, isSelf)
			row.Parent = scrollGrid.Root
		end
	end

	refreshFooter()
end

local function buildFooter(parent: Instance): Frame
	local footer = Util.Create("Frame", {
		Name = "OwnRowFooter",
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 48),
		Visible = false,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = footer })
	Util.Create("UIStroke", {
		Color = Theme.Color.AccentInfo,
		Thickness = Theme.Stroke.Regular,
		Transparency = 0.3,
		Parent = footer,
	})

	footerRankLabel = Util.Create("TextLabel", {
		Name = "Rank",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(0, 70, 1, 0),
		Text = "Unranked",
		TextColor3 = Theme.Color.AccentInfo,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 15,
		Parent = footer,
	}) :: TextLabel

	footerNameLabel = Util.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 88, 0, 0),
		Size = UDim2.new(1, -230, 1, 0),
		Text = "",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 15,
		Parent = footer,
	}) :: TextLabel

	footerValueLabel = Util.Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 140, 1, 0),
		Text = "0",
		TextColor3 = Theme.Color.AccentPrimary,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Font.Mono,
		TextSize = 15,
		Parent = footer,
	}) :: TextLabel

	footerFrame = footer
	return footer
end

function LeaderboardUI.Init(): Frame
	local modal = UIKit.Modal.new({
		Title = "LEADERBOARDS",
		Subtitle = "Top players across every server - refreshes automatically.",
		Size = UDim2.fromOffset(720, 560),
	})

	UIKit.TabBar.new({
		Parent = modal.Content,
		Size = UDim2.new(1, 0, 0, 36),
		Tabs = (function()
			local tabs = {}
			for _, key in TAB_ORDER do
				table.insert(tabs, { Id = key, Label = TAB_LABELS[key] })
			end
			return tabs
		end)(),
		OnChange = function(tabId: string)
			activeTab = tabId
			renderTab(activeTab)
		end,
	})

	updatedLabel = Util.Create("TextLabel", {
		Name = "UpdatedLabel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "not loaded yet",
		TextColor3 = Theme.Color.TextDisabled,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 12,
		Parent = modal.Content,
	}) :: TextLabel

	local divider = UIKit.Divider.new({
		Parent = modal.Content,
		LayoutOrder = 1,
	})
	divider.Position = UDim2.new(0, 0, 0, 64)

	local grid = UIKit.ScrollGrid.new({
		Parent = modal.Content,
		Position = UDim2.new(0, 0, 0, 74),
		Size = UDim2.new(1, 0, 1, -132),
		Vertical = true,
	})
	scrollGrid = grid

	local footer = buildFooter(modal.Content)
	footer.Position = UDim2.new(0, 0, 1, -50)

	renderTab(activeTab)

	-- Re-render the "Ns ago" label every few seconds even without a fresh
	-- server push, so the number keeps climbing instead of looking frozen.
	task.spawn(function()
		while true do
			task.wait(5)
			if updatedLabel then
				local board = currentState.Boards[activeTab]
				updatedLabel.Text = if board then formatAgo(board.UpdatedAt) else "not loaded yet"
			end
		end
	end)

	return modal.Root
end

function LeaderboardUI.SetState(state: LeaderboardState)
	currentState = state
	renderTab(activeTab)
end

return LeaderboardUI
