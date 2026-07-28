--!strict
-- Builds the Store screen (Upgrades / Boosts / Consumables tabs) from UIKit
-- primitives. Pure presentation: this module never spends currency itself -
-- it calls back into StoreController on a buy click, and only updates what it
-- shows once the server confirms via Store_StateUpdated / Store_PurchaseResult.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreConfig = require(ReplicatedStorage.Shared.Store.StoreConfig)
local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local StoreUI = {}

export type StoreUIState = {
	Upgrades: { [string]: number },
	Boosts: { [string]: number }, -- family -> seconds remaining
}

export type StoreUICallbacks = {
	OnPurchase: (category: string, itemId: string) -> (),
}

local DEFAULT_STATE: StoreUIState = { Upgrades = {}, Boosts = {} }

local currentState: StoreUIState = DEFAULT_STATE

-- family -> os.clock() timestamp at which that boost family's active window
-- ends, derived from the last StateUpdated push. Ticked locally each second
-- so the countdown doesn't need a server round trip to move.
local boostLocalExpiry: { [string]: number } = {}
-- family -> list of countdown labels to keep in sync (one boost family can
-- have multiple purchasable duration tiers, each shown as its own card).
local boostCountdownLabels: { [string]: { TextLabel } } = {}

type UpgradeRowRefs = {
	ProgressBar: any, -- UIKit.ProgressBarHandle
	TierLabel: TextLabel,
	BuyButton: TextButton,
	Def: StoreConfig.UpgradeDefinition,
}

local upgradeRows: { [string]: UpgradeRowRefs } = {}

local callbacks: StoreUICallbacks? = nil

local function formatCurrency(amount: number, currency: string): string
	local formatted = tostring(math.floor(amount)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return `{formatted} {currency}`
end

local function formatDuration(totalSeconds: number): string
	local minutes = math.floor(totalSeconds / 60)
	local hours = math.floor(minutes / 60)
	if hours > 0 then
		return `{hours}h {minutes % 60}m`
	end
	return `{minutes}m`
end

local function formatCountdown(secondsRemaining: number): string
	local total = math.max(0, math.floor(secondsRemaining))
	local minutes = math.floor(total / 60)
	local seconds = total % 60
	return string.format("%d:%02d", minutes, seconds)
end

-- === Upgrades tab =============================================================

local function buildUpgradeRow(parent: Instance, def: StoreConfig.UpgradeDefinition, layoutOrder: number)
	local row = Util.Create("Frame", {
		Name = `Row_{def.Id}`,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 108),
		LayoutOrder = layoutOrder,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = row })
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Spacing.S),
		PaddingBottom = UDim.new(0, Theme.Spacing.S),
		PaddingLeft = UDim.new(0, Theme.Spacing.M),
		PaddingRight = UDim.new(0, Theme.Spacing.M),
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 0, 22),
		Text = def.Name,
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		Parent = row,
	})

	Util.Create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(0.6, 0, 0, 34),
		Text = def.Description,
		TextColor3 = Theme.Color.TextSecondary,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Theme.Font.Body,
		TextSize = 12,
		Parent = row,
	})

	local tierLabel = Util.Create("TextLabel", {
		Name = "TierLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 100, 0, 22),
		Text = `Tier 0/{def.MaxTier}`,
		TextColor3 = Theme.RarityColor(if def.Currency == "Gems" then "Epic" else "Rare"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Font.Mono,
		TextSize = 13,
		Parent = row,
	}) :: TextLabel

	local progressBar = UIKit.ProgressBar.new({
		Parent = row,
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.new(1, 0, 0, 16),
		AccentColor = if def.Currency == "Gems" then Theme.Color.AccentSecondary else Theme.Color.AccentPrimary,
		ShowLabel = false,
	})

	local buyButton = UIKit.Button.new({
		Parent = row,
		Text = "...",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 82),
		Variant = if def.Currency == "Gems" then "Secondary" else "Primary",
		OnClick = function()
			if callbacks then
				callbacks.OnPurchase("Upgrade", def.Id)
			end
		end,
	})

	upgradeRows[def.Id] = {
		ProgressBar = progressBar,
		TierLabel = tierLabel,
		BuyButton = buyButton,
		Def = def,
	}
end

local function refreshUpgradeRow(id: string)
	local refs = upgradeRows[id]
	if not refs then
		return
	end
	local def = refs.Def
	local tier = currentState.Upgrades[id] or 0

	refs.TierLabel.Text = `Tier {tier}/{def.MaxTier}`
	refs.ProgressBar:SetProgress(tier, def.MaxTier)

	if tier >= def.MaxTier then
		refs.BuyButton.Text = "MAXED"
	else
		local price = def.PriceForTier(tier + 1)
		refs.BuyButton.Text = `Upgrade - {formatCurrency(price, def.Currency)}`
	end
end

local function buildUpgradesTab(parent: Instance)
	local scroll = UIKit.ScrollGrid.new({ Parent = parent, Vertical = true })
	for index, id in StoreConfig.UpgradeOrder do
		local def = StoreConfig.GetUpgrade(id)
		if def then
			buildUpgradeRow(scroll.Root, def, index)
		end
	end
	return scroll.Root
end

-- === Boosts tab ===============================================================

local function buildBoostsTab(parent: Instance)
	local scroll = UIKit.ScrollGrid.new({
		Parent = parent,
		CellSize = UDim2.fromOffset(210, 150),
	})

	for index, id in StoreConfig.BoostOrder do
		local def = StoreConfig.GetBoost(id)
		if not def then
			continue
		end

		local card = UIKit.ItemCard.new({
			Parent = scroll.Root,
			LayoutOrder = index,
			Rarity = if def.Family == "Luck2x" then "Secret" elseif def.Family == "XP2x" then "Epic" else "Rare",
			Title = def.Name,
			Subtitle = formatDuration(def.DurationSeconds),
			FooterText = formatCurrency(def.Price, def.Currency),
			OnFooterClick = function()
				if callbacks then
					callbacks.OnPurchase("Boost", def.Id)
				end
			end,
		})

		local countdown = Util.Create("TextLabel", {
			Name = "Countdown",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(60, 16),
			Text = "",
			TextColor3 = Theme.Color.AccentWarning,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.Font.Mono,
			TextSize = 11,
			ZIndex = 4,
			Parent = card.Root,
		}) :: TextLabel

		boostCountdownLabels[def.Family] = boostCountdownLabels[def.Family] or {}
		table.insert(boostCountdownLabels[def.Family], countdown)
	end

	return scroll.Root
end

-- === Consumables tab ==========================================================

local function buildConsumablesTab(parent: Instance)
	local scroll = UIKit.ScrollGrid.new({
		Parent = parent,
		CellSize = UDim2.fromOffset(210, 150),
	})

	for index, id in StoreConfig.ConsumableOrder do
		local def = StoreConfig.GetConsumable(id)
		if not def then
			continue
		end

		UIKit.ItemCard.new({
			Parent = scroll.Root,
			LayoutOrder = index,
			Rarity = "Epic",
			Title = def.Name,
			Subtitle = def.Description,
			FooterText = formatCurrency(def.Price, def.Currency),
			OnFooterClick = function()
				if callbacks then
					callbacks.OnPurchase("Consumable", def.Id)
				end
			end,
		})
	end

	return scroll.Root
end

-- === Countdown ticking =========================================================

local function tickCountdowns()
	local now = os.clock()
	for family, labels in boostCountdownLabels do
		local expiry = boostLocalExpiry[family]
		local remaining = if expiry then math.max(0, expiry - now) else 0
		local text = if remaining > 0 then `Active {formatCountdown(remaining)}` else ""
		for _, label in labels do
			label.Text = text
		end
	end
end

-- === Public API ================================================================

function StoreUI.Init(initCallbacks: StoreUICallbacks): Frame
	callbacks = initCallbacks

	local modal = UIKit.Modal.new({
		Title = "STORE",
		Subtitle = "Upgrades, boosts and consumables - spend Coins or Gems earned in-game.",
		Size = UDim2.fromOffset(820, 560),
	})

	local tabContentHolder = Util.Create("Frame", {
		Name = "TabContent",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		Parent = modal.Content,
	}) :: Frame

	local upgradesFrame = buildUpgradesTab(tabContentHolder)
	local boostsFrame = buildBoostsTab(tabContentHolder)
	local consumablesFrame = buildConsumablesTab(tabContentHolder)
	boostsFrame.Visible = false
	consumablesFrame.Visible = false

	UIKit.TabBar.new({
		Parent = modal.Content,
		Size = UDim2.new(1, 0, 0, 36),
		Tabs = {
			{ Id = "Upgrades", Label = "UPGRADES" },
			{ Id = "Boosts", Label = "BOOSTS" },
			{ Id = "Consumables", Label = "CONSUMABLES" },
		},
		OnChange = function(tabId: string)
			upgradesFrame.Visible = tabId == "Upgrades"
			boostsFrame.Visible = tabId == "Boosts"
			consumablesFrame.Visible = tabId == "Consumables"
		end,
	})

	-- Local per-second countdown ticker for active boosts. Cheap (a handful of
	-- label writes) and only does anything once at least one boost is active.
	task.spawn(function()
		while true do
			task.wait(1)
			tickCountdowns()
		end
	end)

	for id in pairs(StoreConfig.Upgrades) do
		refreshUpgradeRow(id)
	end

	return modal.Root
end

function StoreUI.SetState(state: StoreUIState)
	currentState = state

	for id in pairs(StoreConfig.Upgrades) do
		refreshUpgradeRow(id)
	end

	local now = os.clock()
	for family, secondsRemaining in state.Boosts do
		boostLocalExpiry[family] = now + secondsRemaining
	end
	tickCountdowns()
end

return StoreUI
