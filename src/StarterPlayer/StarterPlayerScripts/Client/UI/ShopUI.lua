--!strict
-- Builds the Shop panel (Game Passes + Products tabs) with UIKit primitives.
-- Pure UI construction only - never grants currency or perks itself, never
-- decides what a player owns. It renders whatever ShopConfig says exists and
-- whatever ShopController tells it about ownership, and forwards buy clicks
-- back to ShopController via the callbacks passed to Init().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local Util = UIKit.Util

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local ShopUI = {}

export type ShopUICallbacks = {
	OnBuyGamePass: (passKey: string) -> (),
	OnBuyProduct: (productKey: string) -> (),
}

local PANEL_SIZE = UDim2.new(0, 640, 0, 480)
local ROBUX_TEXT_COLOR = Color3.fromRGB(10, 20, 14) -- dark text for contrast on Theme.Color.Robux
local ACTIVE_TAB_TEXT_COLOR = Color3.fromRGB(10, 20, 14) -- dark text for contrast on the active tab's accent fill

-- The nav/panel id this screen registers with Shell. Shared between
-- RegisterNavButton's Id and the Modal's OnClose callback so clicking the
-- Modal's own [X] keeps Shell's panel-registry state (openPanelId, nav icon
-- highlight) in sync instead of only hiding the Frame.
local PANEL_ID = "NavShop"

local initialized = false
local activeTab = "GamePasses"

local rootPanel: Frame? = nil
local gamePassesScroll: ScrollingFrame? = nil
local productsScroll: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local gamePassButtons: { [string]: TextButton } = {}

-- Buy-button visual states -----------------------------------------------
--
-- A card's button reads one of three ways:
--   * "Coming soon" (disabled, muted) - real id, not test mode: Id is still
--     the `0` placeholder and we are NOT in Studio test mode, so a real
--     player must never see a button that looks live but does nothing.
--   * "TEST BUY" (Robux-colored, active) - ShopConfig.IsTestModeForId(id) is
--     true: Studio + placeholder id, so clicking simulates the purchase.
--   * "R$  Buy" (Robux-colored, active) - a real, non-zero id: a normal
--     MarketplaceService prompt.
local function applyBuyButtonState(button: TextButton, id: number)
	if ShopConfig.IsTestModeForId(id) then
		button.Text = "TEST BUY"
		button.BackgroundColor3 = Theme.Color.Robux
		button.TextColor3 = ROBUX_TEXT_COLOR
		button.Active = true
		button.AutoButtonColor = false
	elseif id == 0 then
		button.Text = "Coming soon"
		button.BackgroundColor3 = Theme.Color.Background
		button.TextColor3 = Theme.Color.TextDisabled
		button.Active = false
		button.AutoButtonColor = false
	else
		button.Text = "R$  Buy"
		button.BackgroundColor3 = Theme.Color.Robux
		button.TextColor3 = ROBUX_TEXT_COLOR
		button.Active = true
		button.AutoButtonColor = false
	end
end

local function createBuyButton(parent: Instance, id: number, onClick: () -> ()): TextButton
	local button = UIKit.Button.new({
		Text = "R$  Buy",
		Variant = "Primary",
		Size = UDim2.new(0, 130, 0, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Parent = parent,
		OnClick = onClick,
	})
	-- Roblox brand guideline: the Robux-green accent is reserved for actual
	-- Robux price affordances, so Theme.Color.Robux only ever appears on
	-- these buy buttons (never on the disabled "Coming soon" state).
	applyBuyButtonState(button, id)
	return button
end

local function createGamePassCard(
	parent: Instance,
	passConfig: ShopConfig.GamePassDefinition,
	layoutOrder: number,
	onBuy: (string) -> ()
): TextButton
	local card = Util.Create("Frame", {
		Name = passConfig.Key,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 86),
		LayoutOrder = layoutOrder,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -170, 0, 22),
		Text = passConfig.Name,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 36),
		Size = UDim2.new(1, -170, 0, 40),
		Text = passConfig.Description,
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.Body,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	return createBuyButton(card, passConfig.Id, function()
		onBuy(passConfig.Key)
	end)
end

local function createProductCard(
	parent: Instance,
	productConfig: ShopConfig.ProductDefinition,
	layoutOrder: number,
	onBuy: (string) -> ()
)
	local accent = if productConfig.Currency == Constants.CURRENCY.HARD
		then Theme.Color.AccentSecondary
		else Theme.Color.AccentPrimary

	local card = Util.Create("Frame", {
		Name = productConfig.Key,
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 86),
		LayoutOrder = layoutOrder,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(1, -170, 0, 20),
		Text = productConfig.Name,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 32),
		Size = UDim2.new(1, -170, 0, 18),
		Text = `+{productConfig.Amount} {productConfig.Currency}`,
		TextColor3 = accent,
		Font = Theme.Font.SubHeading,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	Util.Create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 54),
		Size = UDim2.new(1, -170, 0, 24),
		Text = productConfig.Description,
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.Body,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	createBuyButton(card, productConfig.Id, function()
		onBuy(productConfig.Key)
	end)
end

local function createSectionHeader(parent: Instance, text: string, layoutOrder: number)
	Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		Text = text,
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.SubHeading,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
end

local function createScrollList(parent: Instance, visible: boolean): ScrollingFrame
	local scroll = Util.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Stroke,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
		Visible = visible,
		Parent = parent,
	}) :: ScrollingFrame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	return scroll
end

local function setActiveTab(tabKey: string)
	activeTab = tabKey

	if gamePassesScroll then
		gamePassesScroll.Visible = tabKey == "GamePasses"
	end
	if productsScroll then
		productsScroll.Visible = tabKey == "Products"
	end

	for key, button in tabButtons do
		local isActive = key == tabKey
		button.BackgroundColor3 = if isActive then Theme.Color.AccentPrimary else Theme.Color.Surface
		button.TextColor3 = if isActive then ACTIVE_TAB_TEXT_COLOR else Theme.Color.TextSecondary
	end
end

local function buildTabBar(parent: Instance)
	local tabBar = Util.Create("Frame", {
		Name = "TabBar",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = parent,
	}) :: Frame

	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = tabBar,
	})

	tabButtons.GamePasses = UIKit.Button.new({
		Text = "Game Passes",
		Variant = "Secondary",
		Size = UDim2.new(0, 160, 1, 0),
		Parent = tabBar,
		OnClick = function()
			setActiveTab("GamePasses")
		end,
	})

	tabButtons.Products = UIKit.Button.new({
		Text = "Products",
		Variant = "Secondary",
		Size = UDim2.new(0, 160, 1, 0),
		Parent = tabBar,
		OnClick = function()
			setActiveTab("Products")
		end,
	})
end

local function buildContent(parent: Instance, callbacks: ShopUICallbacks)
	local contentContainer = Util.Create("Frame", {
		Name = "Lists",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = parent,
	}) :: Frame

	gamePassesScroll = createScrollList(contentContainer, true)
	productsScroll = createScrollList(contentContainer, false)

	for index, key in ShopConfig.GamePassOrder do
		local passConfig = ShopConfig.GamePasses[key]
		gamePassButtons[key] = createGamePassCard(gamePassesScroll :: ScrollingFrame, passConfig, index, callbacks.OnBuyGamePass)
	end

	local order = 0
	local function addProductGroup(currency: string, headerText: string)
		order += 1
		createSectionHeader(productsScroll :: ScrollingFrame, headerText, order)
		for _, key in ShopConfig.ProductOrder do
			local productConfig = ShopConfig.Products[key]
			if productConfig.Currency == currency then
				order += 1
				createProductCard(productsScroll :: ScrollingFrame, productConfig, order, callbacks.OnBuyProduct)
			end
		end
	end

	addProductGroup(Constants.CURRENCY.HARD, "GEMS")
	addProductGroup(Constants.CURRENCY.SOFT, "COINS")
end

-- Returns the panel's root Frame so ShopController can pass it as `Panel` to
-- Shell.RegisterNavButton - Shell then owns exclusive show/hide of this
-- screen, so this module never tracks its own `visible` boolean.
function ShopUI.Init(callbacks: ShopUICallbacks): Frame
	if initialized then
		warn("[ShopUI] Init called more than once - ignoring")
		return rootPanel :: Frame
	end
	initialized = true

	local subtitle = if ShopConfig.TEST_MODE
		then "Robux shop - TEST MODE active in Studio (placeholder ids simulate a purchase)"
		else "Robux shop"

	local modal = UIKit.Modal.new({
		Title = "SHOP",
		Subtitle = subtitle,
		Size = PANEL_SIZE,
		AccentColor = Theme.Color.Robux,
		Parent = Shell.GetScreenGui(),
		OnClose = function()
			-- The Modal's own [X] hides the Frame directly; route it back
			-- through Shell so Shell's panel registry (openPanelId, nav icon
			-- highlight) stays in sync instead of drifting out of state.
			Shell.ClosePanel(PANEL_ID)
		end,
	})
	local panel = modal.Root
	panel.Name = "ShopPanel"
	rootPanel = panel

	buildTabBar(modal.Content)
	buildContent(modal.Content, callbacks)

	setActiveTab("GamePasses")

	return panel
end

-- `ownedPasses` is the raw `profile.OwnedGamePasses` map ({ [passId]: true }),
-- pushed straight through from Shop_OwnedPassesUpdated - keyed by numeric
-- Game Pass Id, same as DataService stores it. NOTE: while every pass Id is
-- still the `0` placeholder, this map can only ever have one key (0), so
-- "owning" any one placeholder pass (including via a TEST BUY) shows every
-- other placeholder pass as OWNED too - the same aliasing ShopConfig.lua
-- documents for GetProductById. It resolves itself once real, distinct ids
-- are filled in.
function ShopUI.SetOwnedPasses(ownedPasses: { [number]: boolean })
	for _, key in ShopConfig.GamePassOrder do
		local passConfig = ShopConfig.GamePasses[key]
		local button = gamePassButtons[key]
		if not button then
			continue
		end

		local owned = ownedPasses[passConfig.Id] == true
		if owned then
			button.Text = "OWNED"
			button.BackgroundColor3 = Theme.Color.Surface
			button.TextColor3 = Theme.Color.TextDisabled
			button.Active = false
		else
			applyBuyButtonState(button, passConfig.Id)
		end
	end
end

return ShopUI
