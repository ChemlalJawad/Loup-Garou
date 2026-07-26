--!strict
-- Builds the Eggs screen (Hatch tab, Inventory tab, hatch-reveal overlay, and
-- a shared confirmation dialog for anything destructive) entirely from UIKit
-- components. Owns no remote/network code - EggController pushes data in
-- (SetInventory/ShowHatchReveal) and receives click intents out via the
-- handler callbacks passed to Init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

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
	OnSellBrainrot: (uid: string) -> (),
	OnSellDuplicates: (maxRarity: string) -> (),
	OnMergeBrainrots: (brainrotId: string) -> (),
	OnSetAutoHatch: (enabled: boolean, eggId: string) -> (),
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
local modalRoot: Frame? = nil

local hatchView: Frame? = nil
local inventoryView: Frame? = nil
local inventoryGrid: any = nil -- UIKit.ScrollGrid.ScrollGridHandle
local mergeRow: Frame? = nil

local costLabel: TextLabel? = nil
local pityLabel: TextLabel? = nil
local oddsContainer: Frame? = nil
local eggSelectButtons: { [string]: TextButton } = {}
local hatchButtons: { TextButton } = {}
local autoHatchButton: TextButton? = nil
local autoHatchStatusLabel: TextLabel? = nil

local revealOverlay: Frame? = nil
local revealCardsContainer: ScrollingFrame? = nil
local revealGridHandle: any = nil -- UIKit.ScrollGrid.ScrollGridHandle

local confirmOverlay: Frame? = nil
local confirmMessageLabel: TextLabel? = nil
local confirmCallback: (() -> ())? = nil

local selectedEggId: string = EggConfig.EggOrder[1]
local autoHatchEnabled = false

local lastOwned: { OwnedBrainrot } = {}

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
-- Confirmation dialog - shared by per-card sell, bulk sell, and merge, so
-- destroying a duplicate (or worse, a Legendary) always requires an explicit
-- second click.
--------------------------------------------------------------------------

local function buildConfirmDialog(screenGui: ScreenGui)
	local overlay = Util.Create("Frame", {
		Name = "EggConfirmOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		Parent = screenGui,
	}) :: Frame

	local box = UIKit.Panel.new({
		Name = "ConfirmBox",
		Parent = overlay,
		Size = UDim2.fromOffset(380, 220),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Raised = true,
		Padding = Theme.Spacing.L,
	})
	box.ZIndex = 31

	Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Text = "ARE YOU SURE?",
		TextColor3 = Theme.Color.AccentWarning,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 18,
		ZIndex = 32,
		Parent = box,
	})

	local message = Util.Create("TextLabel", {
		Name = "Message",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 110),
		Text = "",
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Theme.Font.Body,
		TextSize = 15,
		ZIndex = 32,
		Parent = box,
	}) :: TextLabel
	confirmMessageLabel = message

	local buttonRow = Util.Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 32,
		Parent = box,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		Parent = buttonRow,
	})

	UIKit.Button.new({
		Text = "Cancel",
		Variant = "Ghost",
		Size = UDim2.new(0, 150, 0, 40),
		Parent = buttonRow,
		OnClick = function()
			overlay.Visible = false
			confirmCallback = nil
		end,
	})

	UIKit.Button.new({
		Text = "Confirm",
		Variant = "Danger",
		Size = UDim2.new(0, 150, 0, 40),
		Parent = buttonRow,
		OnClick = function()
			local callback = confirmCallback
			overlay.Visible = false
			confirmCallback = nil
			if callback then
				callback()
			end
		end,
	})

	confirmOverlay = overlay
end

local function requestConfirm(message: string, onConfirm: () -> ())
	if not confirmOverlay or not confirmMessageLabel then
		-- Defensive fallback only - Init always builds this before any button
		-- that calls requestConfirm can be clicked.
		onConfirm()
		return
	end
	confirmMessageLabel.Text = message
	confirmCallback = onConfirm
	confirmOverlay.Visible = true
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

	if pityLabel then
		local threshold = EggConfig.PityThreshold[selectedEggId]
		if threshold then
			pityLabel.Text = `Pity: guaranteed {EggConfig.PityFloorRarity}-or-better within {threshold} hatches of this egg. (Resets on rejoin.)`
		else
			pityLabel.Text = ""
		end
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
	-- Auto-hatch tracks whichever egg is currently selected while it's on, so
	-- switching eggs mid-session doesn't require toggling it off and back on.
	if autoHatchEnabled and handlers then
		handlers.OnSetAutoHatch(true, selectedEggId)
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

local function buildAutoHatchRow(parent: Instance): Frame
	local row = Util.Create("Frame", {
		Name = "AutoHatchRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})

	local button = UIKit.Button.new({
		Text = "AUTO-HATCH: OFF",
		Variant = "Secondary",
		Size = UDim2.new(0, 220, 0, 40),
		Parent = row,
		OnClick = function()
			autoHatchEnabled = not autoHatchEnabled

			if autoHatchButton then
				autoHatchButton.Text = if autoHatchEnabled then "AUTO-HATCH: ON" else "AUTO-HATCH: OFF"
				autoHatchButton.BackgroundColor3 = if autoHatchEnabled
					then Theme.Color.AccentPrimary
					else Theme.Color.Surface
			end
			if autoHatchStatusLabel then
				local egg = EggConfig.GetEgg(selectedEggId)
				autoHatchStatusLabel.Text = if autoHatchEnabled
					then `Auto-hatching {if egg then egg.Name else selectedEggId}... stops itself if you run out of room or currency.`
					else "Auto-hatch is off."
			end
			if handlers then
				handlers.OnSetAutoHatch(autoHatchEnabled, selectedEggId)
			end
		end,
	})
	autoHatchButton = button

	local status = Util.Create("TextLabel", {
		Name = "AutoHatchStatus",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -232, 1, 0),
		Text = "Auto-hatch is off.",
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 13,
		Parent = row,
	}) :: TextLabel
	autoHatchStatusLabel = status

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

	pityLabel = Util.Create("TextLabel", {
		Name = "PityLabel",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		TextWrapped = true,
		TextColor3 = Theme.Color.AccentInfo,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 12,
		LayoutOrder = 3,
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
		LayoutOrder = 4,
		Parent = view,
	})

	oddsContainer = Util.Create("Frame", {
		Name = "OddsContainer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 140),
		LayoutOrder = 5,
		Parent = view,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		Parent = oddsContainer,
	})

	local autoHatchRow = buildAutoHatchRow(view)
	autoHatchRow.LayoutOrder = 6

	local hatchRow = buildHatchButtonsRow(view)
	hatchRow.LayoutOrder = 7

	return view
end

--------------------------------------------------------------------------
-- Inventory tab
--------------------------------------------------------------------------

local function buildInventoryCard(owned: OwnedBrainrot, equippedUid: string?, layoutOrder: number)
	if not inventoryGrid then
		return
	end
	local isEquipped = owned.Uid == equippedUid
	local rarityIndex = EggConfig.RarityIndex(owned.Rarity) or 1
	local epicIndex = EggConfig.RarityIndex("Epic") or 3
	local refund = Constants.SELL_VALUE[owned.Rarity] or 0

	UIKit.ItemCard.new({
		Parent = inventoryGrid.Root,
		LayoutOrder = layoutOrder,
		Title = EggConfig.DisplayName(owned.Id),
		Rarity = owned.Rarity,
		Subtitle = if isEquipped then "EQUIPPED" else nil,
		Selected = isEquipped,
		OnClick = function()
			if handlers then
				handlers.OnEquipPet(owned.Uid)
			end
		end,
		FooterText = "SELL",
		OnFooterClick = function()
			if isEquipped then
				Shell.Notify("Unequip that Brainrot before selling it.", "Warning")
				return
			end
			local message = `Sell {EggConfig.DisplayName(owned.Id)} ({owned.Rarity}) for {refund} Coins?`
			if rarityIndex >= epicIndex then
				message ..= " This is a high-rarity Brainrot - this cannot be undone."
			end
			requestConfirm(message, function()
				if handlers then
					handlers.OnSellBrainrot(owned.Uid)
				end
			end)
		end,
	})
end

local function refreshMergeRow()
	if not mergeRow then
		return
	end

	for _, child in mergeRow:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local counts: { [string]: number } = {}
	for _, owned in lastOwned do
		counts[owned.Id] = (counts[owned.Id] or 0) + 1
	end

	local order = 0
	for id, count in counts do
		if count >= Constants.MERGE_COST then
			local rarity = EggConfig.RarityOf(id)
			local nextRarity = rarity and EggConfig.NextRarity(rarity)
			if nextRarity then
				order += 1
				UIKit.Button.new({
					Text = `Merge {EggConfig.DisplayName(id)} x{Constants.MERGE_COST} -> {nextRarity}`,
					Variant = "Secondary",
					Size = UDim2.new(0, 280, 0, 36),
					LayoutOrder = order,
					Parent = mergeRow,
					OnClick = function()
						requestConfirm(
							`Consume {Constants.MERGE_COST}x {EggConfig.DisplayName(id)} to create one random {nextRarity} Brainrot? The duplicates used are destroyed and this cannot be undone.`,
							function()
								if handlers then
									handlers.OnMergeBrainrots(id)
								end
							end
						)
					end,
				})
			end
		end
	end
end

local function buildInventoryView(parent: Instance): Frame
	local view = Util.Create("Frame", {
		Name = "InventoryView",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame

	local actionsRow = Util.Create("Frame", {
		Name = "ActionsRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = view,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = actionsRow,
	})

	UIKit.Button.new({
		Text = "Sell Duplicates (Common/Rare)",
		Variant = "Danger",
		Size = UDim2.new(0, 280, 0, 36),
		Parent = actionsRow,
		OnClick = function()
			requestConfirm(
				"Sell every duplicate Common and Rare Brainrot, keeping one of each species plus your equipped one? Epic and above are never touched by this button.",
				function()
					if handlers then
						handlers.OnSellDuplicates("Rare")
					end
				end
			)
		end,
	})

	local mergeRowFrame = Util.Create("Frame", {
		Name = "MergeRow",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = view,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = mergeRowFrame,
	})
	mergeRow = mergeRowFrame

	local grid = UIKit.ScrollGrid.new({
		Parent = view,
		Position = UDim2.new(0, 0, 0, 92),
		Size = UDim2.new(1, 0, 1, -92),
		CellSize = UDim2.fromOffset(150, 170),
		CellPadding = UDim2.fromOffset(12, 12),
	})
	inventoryGrid = grid

	return view
end

--------------------------------------------------------------------------
-- Hatch reveal overlay - the money moment. No mesh assets exist so this
-- leans on motion + rarity color: a short suspense beat (longer the better
-- the best pull is), then cards popping in on a stagger with escalating
-- emphasis (bigger scale-in, longer hold, thicker/pulsing glow) the higher
-- the rarity. A grid (not a horizontal scroller) keeps x10 readable at once.
--------------------------------------------------------------------------

type RarityEmphasis = {
	ScaleStart: number,
	HoldSeconds: number,
	StrokeThickness: number,
	Pulse: boolean,
}

local rarityEmphasis: { [string]: RarityEmphasis } = {
	Common = { ScaleStart = 0.85, HoldSeconds = 0, StrokeThickness = Theme.Stroke.Thin, Pulse = false },
	Rare = { ScaleStart = 0.8, HoldSeconds = 0, StrokeThickness = Theme.Stroke.Regular, Pulse = false },
	Epic = { ScaleStart = 0.7, HoldSeconds = 0.08, StrokeThickness = Theme.Stroke.Regular, Pulse = false },
	Legendary = { ScaleStart = 0.55, HoldSeconds = 0.2, StrokeThickness = Theme.Stroke.Thick, Pulse = true },
	Secret = { ScaleStart = 0.4, HoldSeconds = 0.35, StrokeThickness = Theme.Stroke.Thick, Pulse = true },
}

local function buildRevealCard(entry: HatchResultEntry, layoutOrder: number)
	if not revealCardsContainer then
		return
	end

	local color = Theme.RarityColor(entry.Rarity)
	local emphasis = rarityEmphasis[entry.Rarity] or rarityEmphasis.Common

	local card = Util.Create("Frame", {
		Name = "RevealCard",
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(150, 170),
		LayoutOrder = layoutOrder,
		Parent = revealCardsContainer,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })

	-- Scale via UIScale (not the card's own Size) so the grid layout's cell
	-- placement is unaffected by the pop-in animation.
	local scale = Util.Create("UIScale", { Scale = emphasis.ScaleStart, Parent = card }) :: UIScale

	local stroke = Util.Create("UIStroke", {
		Color = color,
		Thickness = emphasis.StrokeThickness,
		Transparency = 1,
		Parent = card,
	}) :: UIStroke

	local wash = Util.Create("Frame", {
		Name = "Wash",
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = card,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = wash })
	Util.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = wash,
	})

	local nameLabel = Util.Create("TextLabel", {
		Name = "PetName",
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Position = UDim2.new(0, 8, 0, 60),
		Size = UDim2.new(1, -16, 0, 64),
		Text = EggConfig.DisplayName(entry.Id),
		TextWrapped = true,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 15,
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

	local staggerDelay = (layoutOrder - 1) * 0.12
	task.delay(staggerDelay, function()
		if not card.Parent then
			return
		end
		local duration = Theme.Motion.Slow + emphasis.HoldSeconds
		Util.Tween(card, { BackgroundTransparency = 0.05 }, duration)
		Util.Tween(scale, { Scale = 1 }, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		Util.Tween(stroke, { Transparency = 0 }, duration)
		Util.Tween(wash, { BackgroundTransparency = 0.7 }, duration)
		Util.Tween(nameLabel, { TextTransparency = 0 }, duration)
		Util.Tween(badge, { BackgroundTransparency = 0, TextTransparency = 0 }, duration)

		if emphasis.Pulse then
			task.delay(duration, function()
				if not card.Parent then
					return
				end
				local pulseInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				TweenService:Create(stroke, pulseInfo, { Transparency = 0.4 }):Play()
			end)
		end
	end)
end

local function buildRevealOverlay(screenGui: ScreenGui)
	local overlay = Util.Create("Frame", {
		Name = "EggRevealOverlay",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 25,
		Parent = screenGui,
	}) :: Frame

	local revealPanel = UIKit.Panel.new({
		Name = "RevealPanel",
		Parent = overlay,
		Size = UDim2.new(0, 720, 0, 420),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Raised = true,
		Padding = Theme.Spacing.L,
	})
	revealPanel.ZIndex = 26

	Util.Create("TextLabel", {
		Name = "RevealTitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Text = "HATCHED!",
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Heading,
		TextSize = 22,
		ZIndex = 27,
		Parent = revealPanel,
	})

	local grid = UIKit.ScrollGrid.new({
		Parent = revealPanel,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -100),
		CellSize = UDim2.fromOffset(150, 170),
		CellPadding = UDim2.fromOffset(14, 14),
	})
	grid.Root.ZIndex = 27

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
	revealCardsContainer = grid.Root
	revealGridHandle = grid
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function EggUI.Init(inputHandlers: HatchHandlers): Frame
	if modalRoot then
		return modalRoot :: Frame
	end
	handlers = inputHandlers

	local screenGui = Shell.GetScreenGui()

	local modal = UIKit.Modal.new({
		Title = "EGGS",
		Subtitle = "Hatch Brainrots and manage your collection",
		Size = UDim2.fromOffset(760, 580),
		Parent = screenGui,
	})
	modalRoot = modal.Root

	local tabBar = UIKit.TabBar.new({
		Tabs = { { Id = "Hatch", Label = "Hatch" }, { Id = "Inventory", Label = "Inventory" } },
		Parent = modal.Content,
		Size = UDim2.new(0, 280, 0, 40),
		OnChange = function(tabId)
			if hatchView then
				hatchView.Visible = tabId == "Hatch"
			end
			if inventoryView then
				inventoryView.Visible = tabId == "Inventory"
			end
		end,
	})
	tabBar.Root.LayoutOrder = 0

	local content = Util.Create("Frame", {
		Name = "TabContent",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = modal.Content,
	}) :: Frame

	hatchView = buildHatchView(content)
	inventoryView = buildInventoryView(content)

	refreshHatchDetails()

	buildRevealOverlay(screenGui)
	buildConfirmDialog(screenGui)

	return modal.Root
end

function EggUI.ShowHatchReveal(payload: HatchResultPayload)
	local results = payload.Results
	if not payload.Success or not results or #results == 0 then
		return
	end
	if not revealOverlay or not revealGridHandle then
		return
	end

	revealGridHandle:Clear()

	local bestRarityIndex = 1
	for _, entry in results do
		local index = EggConfig.RarityIndex(entry.Rarity) or 1
		if index > bestRarityIndex then
			bestRarityIndex = index
		end
	end
	local legendaryIndex = EggConfig.RarityIndex("Legendary") or 4
	-- Big pulls earn a longer held breath before the cards start flipping in.
	local suspenseSeconds = if bestRarityIndex >= legendaryIndex then 0.5 else 0.15

	local overlay = revealOverlay :: Frame
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	Util.Tween(overlay, { BackgroundTransparency = 0.35 }, Theme.Motion.Normal)

	task.delay(suspenseSeconds, function()
		if not overlay.Visible then
			return
		end
		for index, entry in results do
			buildRevealCard(entry, index)
		end
	end)
end

function EggUI.SetInventory(owned: { OwnedBrainrot }, equippedUid: string?)
	lastOwned = owned

	if inventoryGrid then
		inventoryGrid:Clear()
		for index, entry in owned do
			buildInventoryCard(entry, equippedUid, index)
		end
	end

	refreshMergeRow()
end

return EggUI
