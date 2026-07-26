--!strict
-- Builds the Eggs screen (Hatch tab + Inventory tab + hatch-reveal overlay)
-- entirely from UIKit components. Owns no remote/network code - EggController
-- pushes data in (SetInventory/ShowHatchReveal) and receives click intents
-- out via the handler callbacks passed to Init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)

local Shell = require(StarterPlayer.StarterPlayerScripts.Client.UI.Shell)

local Util = UIKit.Util

local EggUI = {}

export type HatchHandlers = {
	OnRequestHatch: (eggId: string, hatchCount: number) -> (),
	OnEquipPet: (uid: string) -> (),
}

export type HatchResultEntry = {
	Id: string,
	Rarity: string,
	Uid: string,
}

export type HatchResultPayload = {
	Success: boolean,
	EggId: string?,
	Results: { HatchResultEntry }?,
	Reason: string?,
}

export type OwnedBrainrot = {
	Uid: string,
	Id: string,
	Rarity: string,
	HatchedAt: number,
}

-- Module state (built once in Init).
local handlers: HatchHandlers? = nil
local panel: Frame? = nil
local panelVisible = false

local hatchView: Frame? = nil
local inventoryView: Frame? = nil
local inventoryGrid: ScrollingFrame? = nil

local costLabel: TextLabel? = nil
local oddsContainer: Frame? = nil
local eggSelectButtons: { [string]: TextButton } = {}
local tabButtons: { [string]: TextButton } = {}
local hatchButtons: { TextButton } = {}

local revealOverlay: Frame? = nil
local revealCardsContainer: ScrollingFrame? = nil

local selectedEggId: string = EggConfig.EggOrder[1]

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function formatPercent(value: number): string
	if value == math.floor(value) then
		return string.format("%d%%", value)
	end
	return string.format("%.1f%%", value)
end

local function applySelectedStyle(button: TextButton, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if selected then
		button.BackgroundColor3 = Theme.Color.SurfaceRaised
		if stroke then
			stroke.Color = Theme.Color.AccentPrimary
			stroke.Thickness = Theme.Stroke.Thick
			stroke.Transparency = 0
		end
	else
		button.BackgroundColor3 = Theme.Color.Surface
		if stroke then
			stroke.Color = Theme.Color.Stroke
			stroke.Thickness = Theme.Stroke.Thin
			stroke.Transparency = 0.4
		end
	end
end

--------------------------------------------------------------------------
-- Hatch tab
--------------------------------------------------------------------------

local function refreshOddsDisplay()
	if not oddsContainer then
		return
	end

	for _, child in oddsContainer:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local egg = EggConfig.GetEgg(selectedEggId)
	if not egg then
		return
	end

	local total = 0
	for _, weight in egg.RarityWeights do
		total += weight
	end
	if total <= 0 then
		return
	end

	for order, rarity in Constants.RARITY_ORDER do
		local weight = egg.RarityWeights[rarity]
		if weight then
			local row = Util.Create("Frame", {
				Name = "OddsRow_" .. rarity,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = order,
				Parent = oddsContainer,
			}) :: Frame

			UIKit.RarityBadge.new({
				Parent = row,
				Rarity = rarity,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
			})

			Util.Create("TextLabel", {
				Name = "Percent",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0, 90, 1, 0),
				Text = formatPercent(weight / total * 100),
				TextColor3 = Theme.Color.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Theme.Font.Mono,
				TextSize = 14,
				Parent = row,
			})
		end
	end
end

local function refreshHatchDetails()
	local egg = EggConfig.GetEgg(selectedEggId)
	if not egg then
		return
	end

	if costLabel then
		costLabel.Text = `{egg.Name} - {egg.Cost} {egg.Currency} per hatch`
	end

	for index, count in EggConfig.HatchCounts do
		local button = hatchButtons[index]
		if button then
			button.Text = `x{count}  ({egg.Cost * count} {egg.Currency})`
		end
	end

	for id, button in eggSelectButtons do
		applySelectedStyle(button, id == selectedEggId)
	end

	refreshOddsDisplay()
end

local function selectEgg(eggId: string)
	selectedEggId = eggId
	refreshHatchDetails()
end

local function selectTab(tabId: string)
	if hatchView then
		hatchView.Visible = tabId == "Hatch"
	end
	if inventoryView then
		inventoryView.Visible = tabId == "Inventory"
	end
	for id, button in tabButtons do
		applySelectedStyle(button, id == tabId)
	end
end

local function buildEggSelectorRow(parent: Instance): Frame
	local row = Util.Create("Frame", {
		Name = "EggSelectorRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})

	for index, eggId in EggConfig.EggOrder do
		local egg = EggConfig.GetEgg(eggId)
		if egg then
			local button = UIKit.Button.new({
				Text = egg.Name,
				Variant = "Secondary",
				Size = UDim2.new(0, 150, 0, 40),
				LayoutOrder = index,
				Parent = row,
				OnClick = function()
					selectEgg(eggId)
				end,
			})
			eggSelectButtons[eggId] = button
		end
	end

	return row
end

local function buildHatchButtonsRow(parent: Instance): Frame
	local row = Util.Create("Frame", {
		Name = "HatchButtonsRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = parent,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})

	hatchButtons = {}
	for index, count in EggConfig.HatchCounts do
		local button = UIKit.Button.new({
			Text = `x{count}`,
			Variant = "Primary",
			Size = UDim2.new(0, 150, 0, 48),
			LayoutOrder = index,
			Parent = row,
			OnClick = function()
				if handlers then
					handlers.OnRequestHatch(selectedEggId, count)
				end
			end,
		})
		table.insert(hatchButtons, button)
	end

	return row
end

local function buildHatchView(parent: Instance): Frame
	local view = Util.Create("Frame", {
		Name = "HatchView",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = true,
		Parent = parent,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, Theme.Spacing.M),
		Parent = view,
	})

	local selectorRow = buildEggSelectorRow(view)
	selectorRow.LayoutOrder = 1

	costLabel = Util.Create("TextLabel", {
		Name = "CostLabel",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 15,
		LayoutOrder = 2,
		Parent = view,
	}) :: TextLabel

	Util.Create("TextLabel", {
		Name = "OddsTitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "DROP ODDS",
		TextColor3 = Theme.Color.TextDisabled,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 13,
		LayoutOrder = 3,
		Parent = view,
	})

	oddsContainer = Util.Create("Frame", {
		Name = "OddsContainer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 150),
		LayoutOrder = 4,
		Parent = view,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		Parent = oddsContainer,
	})

	local hatchRow = buildHatchButtonsRow(view)
	hatchRow.LayoutOrder = 5

	return view
end

--------------------------------------------------------------------------
-- Inventory tab
--------------------------------------------------------------------------

local function buildInventoryCard(owned: OwnedBrainrot, equippedUid: string?): TextButton
	local isEquipped = owned.Uid == equippedUid

	local card = Util.Create("TextButton", {
		Name = "Card_" .. owned.Uid,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 128, 0, 128),
		Text = "",
	}) :: TextButton

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })
	Util.Create("UIStroke", {
		Color = if isEquipped then Theme.Color.AccentPrimary else Theme.Color.Stroke,
		Thickness = if isEquipped then Theme.Stroke.Thick else Theme.Stroke.Thin,
		Transparency = if isEquipped then 0 else 0.4,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "PetName",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 44),
		Position = UDim2.new(0, 6, 0, 8),
		Text = EggConfig.DisplayNames[owned.Id] or owned.Id,
		TextWrapped = true,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Body,
		TextSize = 14,
		Parent = card,
	})

	UIKit.RarityBadge.new({
		Parent = card,
		Rarity = owned.Rarity,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
	})

	if isEquipped then
		Util.Create("TextLabel", {
			Name = "EquippedTag",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, 54),
			Text = "EQUIPPED",
			TextColor3 = Theme.Color.AccentPrimary,
			Font = Theme.Font.SubHeading,
			TextSize = 11,
			Parent = card,
		})
	end

	card.MouseButton1Click:Connect(function()
		if handlers then
			handlers.OnEquipPet(owned.Uid)
		end
	end)

	return card
end

local function buildInventoryView(parent: Instance): Frame
	local view = Util.Create("Frame", {
		Name = "InventoryView",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	local scroll = Util.Create("ScrollingFrame", {
		Name = "InventoryGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Stroke,
		Parent = view,
	}) :: ScrollingFrame

	Util.Create("UIGridLayout", {
		CellSize = UDim2.new(0, 128, 0, 128),
		CellPadding = UDim2.new(0, 12, 0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = scroll,
	})

	inventoryGrid = scroll
	return view
end

--------------------------------------------------------------------------
-- Hatch reveal overlay
--------------------------------------------------------------------------

local function buildRevealCard(entry: HatchResultEntry, layoutOrder: number)
	if not revealCardsContainer then
		return
	end

	local color = Theme.RarityColor(entry.Rarity)

	local card = Util.Create("Frame", {
		Name = "RevealCard",
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 140, 1, 0),
		LayoutOrder = layoutOrder,
		Parent = revealCardsContainer,
	}) :: Frame

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })
	local stroke = Util.Create("UIStroke", {
		Color = color,
		Thickness = Theme.Stroke.Thick,
		Transparency = 1,
		Parent = card,
	}) :: UIStroke

	local accent = Util.Create("Frame", {
		Name = "AccentStrip",
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 8),
		Parent = card,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = accent })

	local nameLabel = Util.Create("TextLabel", {
		Name = "PetName",
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Position = UDim2.new(0, 8, 0, 22),
		Size = UDim2.new(1, -16, 0, 64),
		Text = EggConfig.DisplayNames[entry.Id] or entry.Id,
		TextWrapped = true,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		Parent = card,
	}) :: TextLabel

	local badge = UIKit.RarityBadge.new({
		Parent = card,
		Rarity = entry.Rarity,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
	})
	badge.BackgroundTransparency = 1
	badge.TextTransparency = 1

	local staggerDelay = (layoutOrder - 1) * 0.15
	task.delay(staggerDelay, function()
		if not card.Parent then
			return
		end
		Util.Tween(card, { BackgroundTransparency = 0 }, Theme.Motion.Slow)
		Util.Tween(stroke, { Transparency = 0 }, Theme.Motion.Slow)
		Util.Tween(accent, { BackgroundTransparency = 0 }, Theme.Motion.Slow)
		Util.Tween(nameLabel, { TextTransparency = 0 }, Theme.Motion.Slow)
		Util.Tween(badge, { BackgroundTransparency = 0, TextTransparency = 0 }, Theme.Motion.Slow)
	end)
end

local function buildRevealOverlay(screenGui: ScreenGui)
	local overlay = Util.Create("Frame", {
		Name = "EggRevealOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Parent = screenGui,
	}) :: Frame

	local revealPanel = UIKit.Panel.new({
		Name = "RevealPanel",
		Parent = overlay,
		Size = UDim2.new(0, 680, 0, 320),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Raised = true,
		Padding = Theme.Spacing.L,
	})
	revealPanel.ZIndex = 10

	Util.Create("TextLabel", {
		Name = "RevealTitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Text = "HATCHED!",
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Heading,
		TextSize = 22,
		Parent = revealPanel,
	})

	local cardScroll = Util.Create("ScrollingFrame", {
		Name = "RevealCards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -100),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticCanvasSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		Parent = revealPanel,
	}) :: ScrollingFrame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = cardScroll,
	})

	UIKit.Button.new({
		Text = "Continue",
		Variant = "Primary",
		Size = UDim2.new(0, 160, 0, 40),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Parent = revealPanel,
		OnClick = function()
			overlay.Visible = false
		end,
	})

	revealOverlay = overlay
	revealCardsContainer = cardScroll
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function EggUI.Init(inputHandlers: HatchHandlers)
	if panel then
		return
	end
	handlers = inputHandlers

	local screenGui = Shell.GetScreenGui()

	local builtPanel = UIKit.Panel.new({
		Name = "EggPanel",
		Parent = screenGui,
		Size = UDim2.new(0, 720, 0, 520),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Raised = true,
		Padding = Theme.Spacing.L,
	})
	builtPanel.Visible = false
	builtPanel.ZIndex = 5
	panel = builtPanel

	local header = Util.Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = builtPanel,
	}) :: Frame

	Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 200, 1, 0),
		Text = "EGGS",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 22,
		Parent = header,
	})

	local tabRow = Util.Create("Frame", {
		Name = "TabRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 220, 0, 36),
		Parent = header,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		Parent = tabRow,
	})

	tabButtons.Hatch = UIKit.Button.new({
		Text = "Hatch",
		Variant = "Secondary",
		Size = UDim2.new(0, 100, 0, 36),
		Parent = tabRow,
		OnClick = function()
			selectTab("Hatch")
		end,
	})

	tabButtons.Inventory = UIKit.Button.new({
		Text = "Inventory",
		Variant = "Secondary",
		Size = UDim2.new(0, 100, 0, 36),
		Parent = tabRow,
		OnClick = function()
			selectTab("Inventory")
		end,
	})

	UIKit.Button.new({
		Text = "X",
		Variant = "Ghost",
		Size = UDim2.new(0, 36, 0, 36),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Parent = header,
		OnClick = function()
			EggUI.Toggle()
		end,
	})

	local content = Util.Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = builtPanel,
	}) :: Frame

	hatchView = buildHatchView(content)
	inventoryView = buildInventoryView(content)

	selectTab("Hatch")
	refreshHatchDetails()

	buildRevealOverlay(screenGui)
end

function EggUI.Toggle()
	if not panel then
		return
	end
	panelVisible = not panelVisible
	panel.Visible = panelVisible
end

function EggUI.ShowHatchReveal(payload: HatchResultPayload)
	local results = payload.Results
	if not payload.Success or not results then
		return
	end
	if not revealOverlay or not revealCardsContainer then
		return
	end

	for _, child in revealCardsContainer:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for index, entry in results do
		buildRevealCard(entry, index)
	end

	revealOverlay.Visible = true
end

function EggUI.SetInventory(owned: { OwnedBrainrot }, equippedUid: string?)
	if not inventoryGrid then
		return
	end

	for _, child in inventoryGrid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for index, entry in owned do
		local card = buildInventoryCard(entry, equippedUid)
		card.LayoutOrder = index
		card.Parent = inventoryGrid
	end
end

return EggUI
