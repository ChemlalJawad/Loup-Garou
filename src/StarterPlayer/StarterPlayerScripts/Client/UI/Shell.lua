--!strict
-- The persistent HUD shell: top bar (currency + level), a left icon dock for
-- navigation, a panel registry that keeps only one screen open at a time, and
-- toast notifications. Every other screen (Eggs, Shop, Store, Index, Quests,
-- CTF HUD, ...) mounts into the ScreenGui this module owns and registers
-- itself here - this module does not know those systems exist.
--
-- Public contract (do not change these signatures without updating every
-- consumer; a dozen systems call into them):
--   Shell.Init()
--   Shell.GetScreenGui(): ScreenGui
--   Shell.RegisterNavButton({ Id, Label, IconText?, OnClick, Panel?, Order? })
--   Shell.SetCurrency(currencyKey: "Coins" | "Gems", amount: number)
--   Shell.Notify(message: string, kind: "Info" | "Success" | "Warning" | "Error"?)
--   Shell.RegisterPanel(id: string, panel: GuiObject)
--   Shell.OpenPanel(id) / Shell.ClosePanel(id) / Shell.TogglePanel(id) / Shell.CloseAllPanels()
--   Shell.SetLevel(level: number, xp: number, xpForNext: number)
--   Shell.SetMultiplier(multiplier: number)
--
-- The nav dock is a vertical icon strip rather than a horizontal bar because
-- this game ships ~10 nav destinations; a horizontal pill bar runs off-screen
-- past about six. Icons show their label on hover.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local Shell = {}

export type NavButtonProps = {
	Id: string,
	Label: string,
	IconText: string?,
	OnClick: () -> (),
	-- When provided, Shell manages this panel's visibility exclusively: opening
	-- it closes every other registered panel, and the nav icon reflects
	-- open/closed state. `OnClick` still fires (after the visibility change) so
	-- callers can refresh content on open.
	Panel: GuiObject?,
	Order: number?,
}

export type ToastKind = "Info" | "Success" | "Warning" | "Error"

local screenGui: ScreenGui? = nil
local navDock: Frame? = nil
local toastContainer: Frame? = nil
local currencyLabels: { [string]: TextLabel } = {}
local navButtons: { [string]: TextButton } = {}
local panels: { [string]: GuiObject } = {}
local openPanelId: string? = nil
local levelLabel: TextLabel? = nil
local xpFill: Frame? = nil
local multiplierLabel: TextLabel? = nil

local NAV_ICON_SIZE = 46

-- Fakes a soft drop shadow for a rounded panel-like GuiObject: we have no
-- shadow image asset to work with (no import pipeline in this project), so a
-- slightly larger, darker, semi-transparent duplicate sits just behind and
-- below it.
local function addDropShadow(target: GuiObject, cornerRadius: UDim): Frame
	target.ZIndex = 2
	local shadow = Util.Create("Frame", {
		Name = target.Name .. "Shadow",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		AnchorPoint = target.AnchorPoint,
		Position = target.Position + UDim2.new(0, 0, 0, 4),
		Size = target.Size + UDim2.new(0, 10, 0, 10),
		ZIndex = 1,
		Parent = target.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = cornerRadius, Parent = shadow })
	return shadow
end

local function buildTopBar(parent: ScreenGui)
	local topBar = Util.Create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		ZIndex = 5,
		Parent = parent,
	}) :: Frame

	-- Glassy translucent backdrop behind the whole bar, so the HUD reads as one
	-- surface instead of text floating directly over gameplay. A true Gaussian
	-- blur isn't available without a viewport-wide post effect, so this
	-- approximates "glassy" with translucency + a subtle vertical gradient.
	local background = Util.Create("Frame", {
		Name = "Background",
		BackgroundColor3 = Theme.Color.Background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 1,
		Parent = topBar,
	}) :: Frame
	Util.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Color.SurfaceRaised),
			ColorSequenceKeypoint.new(1, Theme.Color.Background),
		}),
		Rotation = 90,
		Parent = background,
	})
	Util.Create("Frame", {
		Name = "BottomSeam",
		BackgroundColor3 = Theme.Color.AccentPrimary,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 1,
		Parent = topBar,
	})

	local logoMark = Util.Create("Frame", {
		Name = "LogoMark",
		BackgroundColor3 = Theme.Color.AccentPrimary,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		Rotation = 45,
		ZIndex = 2,
		Parent = topBar,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = logoMark })

	local title = Util.Create("TextLabel", {
		Name = "GameTitle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.new(0, 250, 1, 0),
		Text = "BRAINROT HATCH WARS",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 18,
		ZIndex = 2,
		Parent = topBar,
	}) :: TextLabel
	Util.Create("UIGradient", {
		Color = ColorSequence.new(Theme.Color.TextPrimary, Theme.Color.AccentPrimary),
		Parent = title,
	})

	-- Level chip + XP bar, centre-left of the bar.
	local levelChip = Util.Create("Frame", {
		Name = "LevelChip",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 304, 0.5, 0),
		Size = UDim2.new(0, 160, 0, 38),
		ZIndex = 2,
		Parent = topBar,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = levelChip })
	Util.Create("UIStroke", {
		Color = Theme.Color.AccentInfo,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = levelChip,
	})

	local lvl = Util.Create("TextLabel", {
		Name = "LevelText",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "LVL 1",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.SubHeading,
		TextSize = 13,
		Parent = levelChip,
	}) :: TextLabel
	levelLabel = lvl

	local xpTrack = Util.Create("Frame", {
		Name = "XPTrack",
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 0, 22),
		Size = UDim2.new(1, -24, 0, 6),
		Parent = levelChip,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = xpTrack })

	local fill = Util.Create("Frame", {
		Name = "XPFill",
		BackgroundColor3 = Theme.Color.AccentInfo,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = xpTrack,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = fill })
	xpFill = fill

	local currencyRow = Util.Create("Frame", {
		Name = "CurrencyRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 40),
		ZIndex = 2,
		Parent = topBar,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = currencyRow,
	})

	local multiplier = Util.Create("TextLabel", {
		Name = "Multiplier",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 74, 0, 34),
		Text = "x1.00",
		TextColor3 = Theme.Color.AccentWarning,
		Font = Theme.Font.Mono,
		TextSize = 14,
		LayoutOrder = 0,
		Visible = false,
		Parent = currencyRow,
	}) :: TextLabel
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = multiplier })
	Util.Create("UIStroke", {
		Color = Theme.Color.AccentWarning,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = multiplier,
	})
	multiplierLabel = multiplier

	local _coinsPill, coinsLabel = UIKit.CurrencyPill.new({
		Parent = currencyRow,
		Label = "0",
		IconText = "C",
		AccentColor = Theme.Color.AccentPrimary,
		LayoutOrder = 1,
	})
	coinsLabel.Name = "CoinsAmount"
	currencyLabels.Coins = coinsLabel

	local _gemsPill, gemsLabel = UIKit.CurrencyPill.new({
		Parent = currencyRow,
		Label = "0",
		IconText = "G",
		AccentColor = Theme.Color.AccentSecondary,
		LayoutOrder = 2,
	})
	gemsLabel.Name = "GemsAmount"
	currencyLabels.Gems = gemsLabel
end

local function buildNavDock(parent: ScreenGui)
	local dock = Util.Create("Frame", {
		Name = "NavDock",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0, NAV_ICON_SIZE + 12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Large, Parent = dock })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.4,
		Parent = dock,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = dock,
	})
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = dock,
	})
	navDock = dock
end

local function buildToastContainer(parent: ScreenGui)
	local container = Util.Create("Frame", {
		Name = "ToastContainer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0, 380, 0, 400),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = parent,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = container,
	})
	toastContainer = container
end

function Shell.Init()
	if screenGui then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Util.Create("ScreenGui", {
		Name = "MainUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	screenGui = gui

	buildTopBar(gui)
	buildNavDock(gui)
	buildToastContainer(gui)
end

function Shell.GetScreenGui(): ScreenGui
	assert(screenGui, "Shell.Init must be called before Shell.GetScreenGui")
	return screenGui :: ScreenGui
end

-- Panel registry ------------------------------------------------------------
--
-- Exactly one registered panel is visible at a time. Systems register their
-- root frame once and then call Shell.TogglePanel(id) (or pass `Panel` to
-- RegisterNavButton and let Shell wire the nav icon for them), which removes
-- the class of bug where two screens sat on top of each other because each
-- system tracked its own `visible` boolean.

local function refreshNavSelection()
	for buttonId, button in navButtons do
		local isOpen = buttonId == openPanelId
		button.BackgroundColor3 = if isOpen then Theme.Color.AccentPrimary else Theme.Color.Background
		button.TextColor3 = if isOpen then Color3.fromRGB(10, 20, 14) else Theme.Color.TextSecondary
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if isOpen then Theme.Color.AccentPrimary else Theme.Color.Stroke
			stroke.Thickness = if isOpen then Theme.Stroke.Regular else Theme.Stroke.Thin
		end
	end
end

function Shell.RegisterPanel(id: string, panel: GuiObject)
	panels[id] = panel
	panel.Visible = false
end

function Shell.ClosePanel(id: string)
	local panel = panels[id]
	if panel then
		panel.Visible = false
	end
	if openPanelId == id then
		openPanelId = nil
		refreshNavSelection()
	end
end

function Shell.CloseAllPanels()
	for _, panel in panels do
		panel.Visible = false
	end
	openPanelId = nil
	refreshNavSelection()
end

function Shell.OpenPanel(id: string)
	local panel = panels[id]
	if not panel then
		return
	end
	for otherId, other in panels do
		if otherId ~= id then
			other.Visible = false
		end
	end
	panel.Visible = true
	openPanelId = id
	refreshNavSelection()
end

function Shell.TogglePanel(id: string)
	if openPanelId == id then
		Shell.ClosePanel(id)
	else
		Shell.OpenPanel(id)
	end
end

function Shell.IsPanelOpen(id: string): boolean
	return openPanelId == id
end

function Shell.RegisterNavButton(props: NavButtonProps)
	assert(navDock, "Shell.Init must be called before Shell.RegisterNavButton")

	if props.Panel then
		Shell.RegisterPanel(props.Id, props.Panel)
	end

	local button = Util.Create("TextButton", {
		Name = props.Id,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		Size = UDim2.new(0, NAV_ICON_SIZE, 0, NAV_ICON_SIZE),
		LayoutOrder = props.Order or 100,
		Text = props.IconText or string.sub(props.Label, 1, 1),
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.SubHeading,
		TextSize = 22,
		Parent = navDock,
	}) :: TextButton
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = button })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Parent = button,
	})

	-- Hover label, anchored to the right of the dock so it never covers the
	-- icons themselves.
	local tooltip = Util.Create("TextLabel", {
		Name = "Tooltip",
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 10, 0.5, 0),
		Size = UDim2.new(0, 118, 0, 30),
		Text = props.Label,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Body,
		TextSize = 14,
		Visible = false,
		ZIndex = 10,
		Parent = button,
	}) :: TextLabel
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = tooltip })
	Util.Create("UIStroke", { Color = Theme.Color.Stroke, Thickness = Theme.Stroke.Thin, Parent = tooltip })

	button.MouseEnter:Connect(function()
		tooltip.Visible = true
		if openPanelId ~= props.Id then
			Util.Tween(button, { BackgroundColor3 = Theme.Color.SurfaceRaised }, Theme.Motion.Fast)
		end
	end)
	button.MouseLeave:Connect(function()
		tooltip.Visible = false
		if openPanelId ~= props.Id then
			Util.Tween(button, { BackgroundColor3 = Theme.Color.Background }, Theme.Motion.Fast)
		end
	end)

	button.MouseButton1Click:Connect(function()
		if props.Panel then
			Shell.TogglePanel(props.Id)
		end
		props.OnClick()
	end)

	navButtons[props.Id] = button
	refreshNavSelection()
end

function Shell.SetCurrency(currencyKey: string, amount: number)
	local label = currencyLabels[currencyKey]
	if label then
		-- Thousands separators: raw six-digit coin counts are hard to read at a
		-- glance, and this HUD is the main place players read their balance.
		local formatted = tostring(math.floor(amount))
		local withSeparators = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		label.Text = withSeparators
	end
end

function Shell.SetLevel(level: number, xp: number, xpForNext: number)
	if levelLabel then
		levelLabel.Text = `LVL {level}`
	end
	if xpFill then
		local ratio = if xpForNext > 0 and xpForNext < math.huge then math.clamp(xp / xpForNext, 0, 1) else 1
		Util.Tween(xpFill, { Size = UDim2.new(ratio, 0, 1, 0) }, Theme.Motion.Normal)
	end
end

function Shell.SetMultiplier(multiplier: number)
	if not multiplierLabel then
		return
	end
	multiplierLabel.Visible = multiplier > 1.001
	multiplierLabel.Text = `x{string.format("%.2f", multiplier)}`
end

function Shell.Notify(message: string, kind: ToastKind?)
	assert(toastContainer, "Shell.Init must be called before Shell.Notify")
	UIKit.Toast.new({
		Parent = toastContainer :: Frame,
		Message = message,
		Kind = kind,
	})
end

return Shell
